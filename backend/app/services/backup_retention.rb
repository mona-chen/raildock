# frozen_string_literal: true

# Decides which backup artifacts a retention policy is allowed to delete.
#
# Retention runs unattended on a schedule, so a misconfiguration here is
# indistinguishable from data loss: `remove_file!` deletes the remote object as
# well as the local file. Three rules keep that safe:
#
#   1. The newest artifact of every backup kind is never expired. A service must
#      always have a restore point, even when nothing new has been captured for
#      longer than the retention window (a broken schedule, a paused job, a
#      datastore that stopped accepting exports).
#   2. Safety-net snapshots taken immediately before an irreversible operation
#      are never expired by policy. They are the only remaining copy of data
#      that no longer exists anywhere else.
#   3. Callers scope the expiration to one schedule and one artifact kind, so a
#      volume schedule can never delete database backups (see
#      BackupSchedule#enforce_retention!).
class BackupRetention
  # Matches DestructionSnapshot::TRIGGERS — duplicated deliberately so this
  # guard keeps working if that service is refactored.
  PROTECTED_TRIGGERS = %w[pre_destroy pre_restore].freeze

  Result = Struct.new(:removed, :retained, keyword_init: true)

  def self.prune(scope, keep:)
    new(scope).prune(keep: keep)
  end

  def initialize(scope)
    @scope = scope
  end

  # Removes artifacts beyond the newest `keep`, except the always-retained set.
  def prune(keep:)
    keep = [ keep.to_i, 1 ].max
    ordered = @scope.order(created_at: :desc, id: :desc).to_a
    doomed = ordered.drop(keep)
    retained = always_retain(ordered)
    removed = 0

    doomed.each do |backup|
      next if retained.include?(backup.id)

      begin
        backup.remove_file!
        removed += 1
      rescue Backup::LastCopyError => e
        # The model-level guard refuses to delete a service's only restore
        # point. A retention sweep must never abort because of one artifact.
        Rails.logger.warn "BackupRetention: #{e.message}"
      end
    end

    Result.new(removed: removed, retained: retained.size)
  end

  private

  def always_retain(ordered)
    protected_ids = ordered.select { |backup| protected?(backup) }.map(&:id)
    newest_ids = ordered.group_by(&:backup_kind).values.map { |backups| backups.max_by { |b| [ b.created_at, b.id ] }.id }

    (protected_ids + newest_ids).uniq
  end

  def protected?(backup)
    PROTECTED_TRIGGERS.include?(backup.metadata&.fetch("trigger", nil).to_s)
  end
end
