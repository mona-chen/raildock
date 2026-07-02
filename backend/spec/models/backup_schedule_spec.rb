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
end
