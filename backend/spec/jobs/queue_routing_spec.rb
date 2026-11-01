require "rails_helper"

RSpec.describe "job queue routing" do
  {
    DeploymentJob => :deployments,
    DeploymentSequenceJob => :deployments,
    BackupJob => :backups,
    VolumeBackupJob => :backups,
    RunDueBackupsJob => :backups,
    RunPostgresPitrJob => :backups,
    PostgresWalArchiveJob => :backups,
    PostgresBaseBackupJob => :backups,
    RestoreDrillJob => :backups,
    RunRecoveryDrillsJob => :backups,
    VerifyBackupDestinationsJob => :backups
  }.each do |job_class, queue|
    it "routes #{job_class} to the #{queue} queue" do
      expect(job_class.queue_name).to eq(queue.to_s)
    end
  end
end
