# frozen_string_literal: true

# Audits everything that could turn into unintended data loss.
#
# The destructive paths in RailDock are now gated behind confirmations and
# pre-destroy snapshots, but a gate is only useful when it can actually pass:
# a datastore with no verified backup destination is one failed deploy away
# from being unrecoverable. This report is the operational view of that risk.
class DataSafetyReport
  Finding = Struct.new(:severity, :code, :message, :subject, :remediation, keyword_init: true) do
    def to_h
      {
        severity: severity,
        code: code,
        message: message,
        subject: subject,
        remediation: remediation
      }
    end
  end

  SEVERITIES = %w[critical warning info].freeze

  def initialize(organization: nil, server: nil)
    @organization = organization
    @server = server
  end

  def call
    findings = []
    findings.concat(unprotected_datastores)
    findings.concat(unprotected_volumes)
    findings.concat(destination_findings)
    findings.concat(local_only_backups)
    findings.concat(pitr_findings)
    findings.concat(detached_backup_findings)

    {
      generated_at: Time.current.iso8601,
      scope: scope_description,
      summary: {
        critical: findings.count { |finding| finding.severity == "critical" },
        warning: findings.count { |finding| finding.severity == "warning" },
        info: findings.count { |finding| finding.severity == "info" }
      },
      findings: findings.map(&:to_h)
    }
  end

  private
    def servers
      @servers ||= begin
        scope = Server.all
        scope = scope.where(organization_id: @organization.id) if @organization
        scope = scope.where(id: @server.id) if @server
        scope.includes(:backup_destinations).to_a
      end
    end

    def services
      @services ||= begin
        scope = Service.all
        scope = scope.where(project_id: Project.where(server_id: servers.map(&:id)).select(:id)) unless @organization.nil? && @server.nil?
        scope = scope.where(project_id: Project.where(server_id: @server.id).select(:id)) if @server
        scope.includes(:storage_mounts, project: :server).to_a
      end
    end

    def scope_description
      return "server:#{@server.name}" if @server
      return "organization:#{@organization.name}" if @organization

      "all"
    end

    # ── Critical: data with no recoverable copy ──────────────

    def unprotected_datastores
      services.select { |service| DestructionSnapshot.datastore?(service) }.filter_map do |service|
        next if remote_restore_point?(service)

        Finding.new(
          severity: "critical",
          code: "unprotected_datastore",
          message: "#{service.name} (#{service.subtype}) has no backup stored on a verified destination",
          subject: subject_for(service),
          remediation: "Add a verified S3/R2 destination and schedule backups, or run a manual backup now."
        )
      end
    end

    def unprotected_volumes
      services.filter_map do |service|
        mounts = DestructionSnapshot.persistent_mounts(service)
        next if mounts.empty?
        next if service.backups.completed.backup_kind_volume.any? { |backup| backup.remote_verified? }

        Finding.new(
          severity: "critical",
          code: "unprotected_volume",
          message: "#{service.name} mounts #{mounts.size} persistent volume(s) with no snapshot on a verified destination",
          subject: subject_for(service),
          remediation: "Create a volume snapshot schedule so mounted data survives losing this host."
        )
      end
    end

    # ── Warning: configuration that cannot protect data ──────

    def destination_findings
      findings = []

      servers.each do |server|
        destinations = server.backup_destinations.to_a
        destinations += server.organization.backup_destinations.to_a if server.organization

        if destinations.empty?
          findings << Finding.new(
            severity: "warning",
            code: "no_backup_destination",
            message: "#{server.name} has no backup destination configured",
            subject: { server_id: server.id, server_name: server.name },
            remediation: "Configure an S3-compatible bucket (AWS S3, R2, MinIO) and verify it."
          )
          next
        end

        destinations.uniq.each do |destination|
          next if destination.usable? && !destination.stale_verification?

          findings << Finding.new(
            severity: "warning",
            code: destination.verified? ? "stale_destination" : "unverified_destination",
            message: "#{destination.name} (bucket #{destination.bucket}) is not verified#{destination.last_error.present? ? ": #{destination.last_error}" : ''}",
            subject: { backup_destination_id: destination.id, server_id: server.id },
            remediation: "Re-run verification, or update credentials/permissions for this bucket."
          )
        end
      end

      findings
    end

    def local_only_backups
      names = services.map { |service| [ service.id, service.name ] }.to_h
      scoped_backups.completed.filter_map do |backup|
        next if backup.backup_copies.any? { |copy| copy.backup_destination_id.present? }

        Finding.new(
          severity: "warning",
          code: "local_only_backup",
          message: "Backup #{backup.id} for #{names[backup.service_id] || backup.source_name || 'detached service'} exists only on this host",
          subject: { backup_id: backup.id, service_id: backup.service_id },
          remediation: "Add a remote destination and re-run the backup so a host failure cannot take the only copy with it."
        )
      end
    end

    # ── Info: recoverable artifacts worth knowing about ──────

    # Point-in-time recovery fails in a way that is easy to miss and expensive
    # to ignore: when the archive destination stops accepting segments, the
    # uploader leaves every WAL file inside the database container's data
    # directory. With `archive_timeout = 60s` that is ~16MB/minute of
    # unbounded growth inside PGDATA, which eventually fills the disk the
    # datastore is running on.
    def pitr_findings
      PostgresPitrConfig.where(service_id: services.map(&:id)).includes(:service).filter_map do |config|
        service = config.service
        next if service.blank?

        if config.status == "error"
          Finding.new(
            severity: "critical",
            code: "pitr_archive_failed",
            message: "Point-in-time recovery for #{service.name} is failing (#{config.last_error.presence || 'no error recorded'}). No WAL is reaching a destination and segments are accumulating inside the datastore.",
            subject: subject_for(service),
            remediation: "Re-verify the archive destination's credentials and connectivity, then confirm WAL segments drain. Check the datastore's free disk space."
          )
        elsif config.enabled? && config.last_wal_archived_at.present? && config.last_wal_archived_at < 2.hours.ago
          Finding.new(
            severity: "warning",
            code: "pitr_archive_stalled",
            message: "Point-in-time recovery for #{service.name} has not shipped a WAL segment since #{config.last_wal_archived_at.utc.iso8601}",
            subject: subject_for(service),
            remediation: "Run the WAL archive job and check for errors; a stalled archive also grows the container's disk usage."
          )
        end
      end
    end

    def detached_backup_findings
      scoped_backups.detached.completed.map do |backup|
        Finding.new(
          severity: "info",
          code: "detached_backup",
          message: "Backup #{backup.id} (#{backup.source_label.presence || 'unknown source'}) outlived its service and is still restorable",
          subject: { backup_id: backup.id },
          remediation: "Restore into a new service if this data is still needed, or delete it to reclaim storage."
        )
      end
    end

    def scoped_backups
      @scoped_backups ||= begin
        scope = Backup.all
        scope = scope.where(service_id: services.map(&:id)) if @organization || @server
        scope
      end
    end

    def remote_restore_point?(service)
      service.backups.completed.any? { |backup| backup.remote_verified? || backup.remote_copy_available? }
    end

    def subject_for(service)
      {
        service_id: service.id,
        service_name: service.name,
        project_id: service.project_id,
        project_name: service.project&.name,
        server_id: service.project&.server_id
      }
    end
end
