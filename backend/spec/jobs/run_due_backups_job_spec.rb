require "rails_helper"

RSpec.describe RunDueBackupsJob, type: :job do
  it "queues each due schedule once and advances its next run" do
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
end
