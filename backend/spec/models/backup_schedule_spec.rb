require "rails_helper"

RSpec.describe BackupSchedule, type: :model do
  let(:service) { create(:service) }

  it "is valid for a database schedule without a storage mount" do
    schedule = service.backup_schedules.new(frequency: "daily", retention_count: 7, backup_kind: "database")
    expect(schedule).to be_valid
  end

  it "defaults backup_kind to database" do
    schedule = service.backup_schedules.new(frequency: "daily", retention_count: 7)
    expect(schedule.backup_kind).to eq("database")
  end

  it "is invalid with an unknown backup_kind" do
    schedule = service.backup_schedules.new(frequency: "daily", retention_count: 7, backup_kind: "unknown")
    expect(schedule).not_to be_valid
    expect(schedule.errors[:backup_kind]).to be_present
  end

  it "requires a storage mount for volume schedules" do
    schedule = service.backup_schedules.new(frequency: "daily", retention_count: 7, backup_kind: "volume")
    expect(schedule).not_to be_valid
    expect(schedule.errors[:storage_mount]).to include("is required for volume snapshots")
  end

  it "requires the storage mount to belong to the same service" do
    other_service = create(:service)
    mount = other_service.storage_mounts.create!(host_path: "other-data", container_path: "/data", kind: "volume")

    schedule = service.backup_schedules.new(
      frequency: "daily",
      retention_count: 7,
      backup_kind: "volume",
      storage_mount: mount
    )

    expect(schedule).not_to be_valid
    expect(schedule.errors[:storage_mount]).to include("must belong to this service")
  end

  it "is valid for a volume schedule with a matching storage mount" do
    mount = service.storage_mounts.create!(host_path: "app-data", container_path: "/data", kind: "volume")

    schedule = service.backup_schedules.new(
      frequency: "daily",
      retention_count: 7,
      backup_kind: "volume",
      storage_mount: mount
    )

    expect(schedule).to be_valid
  end

  describe "enabled state" do
    it "defaults new schedules to enabled" do
      schedule = service.backup_schedules.create!(frequency: "daily", retention_count: 7)

      expect(schedule.enabled).to be(true)
    end

    it "excludes paused schedules from the due scope" do
      service.backup_schedules.create!(frequency: "daily", retention_count: 7, next_run_at: 1.minute.ago)
      paused = service.backup_schedules.create!(
        frequency: "daily",
        retention_count: 7,
        next_run_at: 1.minute.ago,
        enabled: false
      )

      expect(BackupSchedule.due).not_to include(paused)
      expect(BackupSchedule.due.count).to eq(1)
    end
  end

  describe ".default_retention_for" do
    it "maps each frequency to a platform-style retention window" do
      expect(described_class.default_retention_for("daily")).to eq(7)
      expect(described_class.default_retention_for("weekly")).to eq(4)
      expect(described_class.default_retention_for("monthly")).to eq(6)
    end

    it "falls back to a week for an unknown frequency" do
      expect(described_class.default_retention_for("hourly")).to eq(7)
    end
  end

  describe "#destination_ids" do
    it "reads destination ids from metadata" do
      schedule = service.backup_schedules.create!(
        frequency: "daily",
        retention_count: 7,
        metadata: { "destination_ids" => [ "dest-1", "dest-2" ] }
      )

      expect(schedule.destination_ids).to eq([ "dest-1", "dest-2" ])
    end

    it "returns an empty array when metadata is blank" do
      schedule = service.backup_schedules.new(frequency: "daily", retention_count: 7)
      expect(schedule.destination_ids).to eq([])
    end
  end

  describe "#enforce_retention!" do
    def scheduled_backup(schedule, kind:, age_minutes:)
      backup = service.backups.create!(
        status: "completed",
        backup_kind: kind,
        metadata: { "schedule_id" => schedule.id }
      )
      backup.update_column(:created_at, age_minutes.minutes.ago)
      backup
    end

    it "expires artifacts beyond this schedule's retention count" do
      schedule = service.backup_schedules.create!(frequency: "daily", retention_count: 2, backup_kind: "database")
      newest = scheduled_backup(schedule, kind: "database", age_minutes: 1)
      middle = scheduled_backup(schedule, kind: "database", age_minutes: 2)
      oldest = scheduled_backup(schedule, kind: "database", age_minutes: 3)

      schedule.enforce_retention!

      expect(Backup.exists?(newest.id)).to be(true)
      expect(Backup.exists?(middle.id)).to be(true)
      expect(Backup.exists?(oldest.id)).to be(false)
    end

    it "never expires a manual or database backup when the schedule snapshots volumes" do
      mount = service.storage_mounts.create!(host_path: "app-data", container_path: "/data", kind: "volume")
      schedule = service.backup_schedules.create!(
        frequency: "daily", retention_count: 1, backup_kind: "volume", storage_mount: mount
      )
      database_backup = scheduled_backup(schedule, kind: "database", age_minutes: 500)
      manual_volume = service.backups.create!(status: "completed", backup_kind: "volume")
      manual_volume.update_column(:created_at, 400.minutes.ago)
      newest_volume = scheduled_backup(schedule, kind: "volume", age_minutes: 1)

      schedule.enforce_retention!

      expect(Backup.exists?(database_backup.id)).to be(true)
      expect(Backup.exists?(manual_volume.id)).to be(true)
      expect(Backup.exists?(newest_volume.id)).to be(true)
    end

    it "leaves artifacts belonging to another schedule alone" do
      schedule = service.backup_schedules.create!(frequency: "daily", retention_count: 1, backup_kind: "database")
      other = service.backup_schedules.create!(frequency: "daily", retention_count: 1, backup_kind: "database")
      other_backup = scheduled_backup(other, kind: "database", age_minutes: 300)
      scheduled_backup(schedule, kind: "database", age_minutes: 1)

      schedule.enforce_retention!

      expect(Backup.exists?(other_backup.id)).to be(true)
    end
  end
end
