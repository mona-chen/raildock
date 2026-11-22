# Re-proves that configured backup destinations still accept writes and serve
# objects back.
#
# A destination is the only thing standing between a failed datastore and
# permanent loss, and the things that break it — rotated keys, tightened bucket
# policies, a renamed R2 endpoint — change without warning. Finding out at
# restore time is too late, so this runs on a schedule and refreshes the same
# `status`/`last_verified_at`/`last_error` fields the recovery UI and
# DataSafetyReport already read.
class VerifyBackupDestinationsJob < ApplicationJob
  queue_as :backups

  # Re-verify anything older than this. Backups run far more often than this,
  # so the schedule (not this window) is what keeps a fresh destination proven.
  MAX_AGE = 7.days
  # Cap the work per run so a big deployment does not stampede the endpoint.
  BATCH_LIMIT = 25

  def perform(max_age: MAX_AGE, limit: BATCH_LIMIT)
    checked = 0
    failed = 0

    # `each`, not `find_each`: find_each replaces the ORDER BY with the primary
    # key, which would re-check the oldest *rows* instead of the stalest
    # proofs.
    stale_destinations(max_age, limit).each do |destination|
      checked += 1
      was_verified = destination.verified?
      begin
        BackupDestinationClient.new(destination).verify!
      rescue => error
        failed += 1
        # verify! already recorded status/last_error on the destination.
        Rails.logger.warn "VerifyBackupDestinationsJob: #{destination.name} (#{destination.bucket}) failed verification: #{error.message}"
        report_outage(destination, error) if was_verified
      end
    end

    { checked: checked, failed: failed }
  end

  private

    def stale_destinations(max_age, limit)
      # `pending` is included: a destination that never completed a probe is
      # exactly the one nobody knows to be usable.
      BackupDestination
        .where(status: %w[verified failed pending])
        .where("last_verified_at IS NULL OR last_verified_at < ?", max_age.ago)
        .order(Arel.sql("last_verified_at ASC NULLS FIRST"), :id)
        .limit(limit)
    end

    # A destination that used to work and stopped is the event worth a warning;
    # one that was already failing would only repeat itself every run.
    # ActivityEvent is project-scoped, so the warning goes to the projects of
    # the organization that owns the destination (or, for a server-scoped one,
    # the server's own organization) — never to other tenants on a shared host.
    def report_outage(destination, error)
      message = "Backup destination #{destination.name} (#{destination.bucket}) stopped accepting backups: " \
                "#{error.message.to_s.truncate(200)}. Backups that use it will fail until it is fixed in Settings → Backups."

      affected_projects(destination).find_each do |project|
        ActivityEvent.create!(
          project: project,
          service_name: "-",
          action: :warning,
          message: message,
          metadata: { "backup_destination_id" => destination.id.to_s }
        )
      end
    rescue => report_error
      Rails.logger.error "VerifyBackupDestinationsJob: could not record outage for #{destination.name}: #{report_error.message}"
    end

    def affected_projects(destination)
      organization_id = destination.organization_id || destination.server&.organization_id
      return Project.none if organization_id.blank?

      scope = Project.where(organization_id: organization_id)
      scope = scope.where(server_id: destination.server_id) if destination.organization_id.blank?
      scope
    end
end
