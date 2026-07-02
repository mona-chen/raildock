require "rails_helper"

RSpec.describe RunDueBackupsJob, type: :job do
  it "queues each due database schedule once and advances its next run" do
    schedule = create(:service, :database).backup_schedules.create!(
      frequency: "daily",
      retention_count: 7,
      next_run_at: 1.minute.ago
    )

    expect {
      described_class.perform_now
    }.to change(Backup, :count).by(1)
      .and have_enqueued_job(BackupJob)

    expect(schedule.reload.last_run_at).to be_present
    expect(schedule.next_run_at).to be > Time.current
  end

  it "queues a volume snapshot when a volume schedule is due" do
    service = create(:service)
    mount = service.storage_mounts.create!(host_path: "app-data", container_path: "/data", kind: "volume")
    schedule = service.backup_schedules.create!(
      frequency: "daily",
      retention_count: 3,
      backup_kind: "volume",
      storage_mount: mount,
      metadata: { "destination_ids" => [ "dest-1" ] },
      next_run_at: 1.minute.ago
    )

    expect {
      described_class.perform_now
    }.to change(Backup, :count).by(1)
      .and have_enqueued_job(VolumeBackupJob)

    backup = Backup.last
    expect(backup.backup_kind).to eq("volume")
    expect(backup.metadata["storage_mount_id"]).to eq(mount.id)
    expect(backup.metadata["destination_ids"]).to eq([ "dest-1" ])

    expect(schedule.reload.last_run_at).to be_present
    expect(schedule.next_run_at).to be > Time.current
  end
end
