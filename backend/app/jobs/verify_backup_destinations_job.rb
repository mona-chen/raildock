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
  queue_as :default

  # Re-verify anything older than this. Backups run far more often than this,
  # so the schedule (not this window) is what keeps a fresh destination proven.
  MAX_AGE = 7.days
  # Cap the work per run so a big deployment does not stampede the endpoint.
  BATCH_LIMIT = 25

  def perform(max_age: MAX_AGE, limit: BATCH_LIMIT)
    checked = 0
    failed = 0

    stale_destinations(max_age, limit).find_each do |destination|
      checked += 1
      BackupDestinationClient.new(destination).verify!
    rescue => error
      failed += 1
      # verify! already recorded status/last_error on the destination; this is
      # the operator-facing breadcrumb.
      Rails.logger.warn "VerifyBackupDestinationsJob: #{destination.name} (#{destination.bucket}) failed verification: #{error.message}"
    end

    { checked: checked, failed: failed }
  end

  private

    def stale_destinations(max_age, limit)
      BackupDestination
        .where(status: %w[verified failed])
        .where("last_verified_at IS NULL OR last_verified_at < ?", max_age.ago)
        .order(Arel.sql("last_verified_at ASC NULLS FIRST"))
        .limit(limit)
    end
end
