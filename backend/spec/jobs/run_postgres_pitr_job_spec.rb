require "rails_helper"

RSpec.describe RunPostgresPitrJob, type: :job do
  let(:server) { create(:server) }
  let(:destination) do
    server.backup_destinations.create!(
      name: "S3", provider: "s3", region: "us-east-1", bucket: "recovery",
      access_key_id: "access", secret_access_key: "secret",
      status: "verified", last_verified_at: Time.current
    )
  end
  let(:service) { create(:service, :database, project: create(:project, server: server)) }
  let!(:config) do
    service.create_postgres_pitr_config!(
      backup_destination: destination, enabled: true, retention_days: 7, status: "active"
    )
  end

  def in_flight_backup(kind, created_at: Time.current)
    service.backups.create!(status: "running", backup_kind: kind).tap do |backup|
      backup.update_columns(created_at: created_at)
    end
  end

  it "enqueues a WAL archive for an enabled config" do
    expect { described_class.perform_now }.to have_enqueued_job(PostgresWalArchiveJob).with(config.id)
  end

  it "does not enqueue an archive while one is already in flight for the config" do
    in_flight_backup("wal")

    expect { described_class.perform_now }.not_to have_enqueued_job(PostgresWalArchiveJob)
  end

  it "ignores a stale in-flight artifact so a killed job cannot wedge PITR" do
    in_flight_backup("wal", created_at: 2.hours.ago)

    expect { described_class.perform_now }.to have_enqueued_job(PostgresWalArchiveJob).with(config.id)
  end

  it "backs off a config that just failed instead of retrying on every tick" do
    config.update!(status: "error", last_error: "Aws::S3::Errors::Http522Error")

    expect { described_class.perform_now }.not_to have_enqueued_job(PostgresWalArchiveJob)
  end

  it "retries once the backoff window has passed" do
    config.update!(status: "error", last_error: "boom")
    config.update_columns(updated_at: (PostgresPitrConfig::RETRY_BACKOFF + 1.minute).ago)

    expect { described_class.perform_now }.to have_enqueued_job(PostgresWalArchiveJob).with(config.id)
  end

  it "takes a base backup when the last one is more than a day old" do
    config.update_columns(last_base_backup_at: 25.hours.ago)

    expect { described_class.perform_now }.to have_enqueued_job(PostgresBaseBackupJob).with(config.id)
  end

  it "skips disabled configs" do
    config.update!(enabled: false)

    expect { described_class.perform_now }.not_to have_enqueued_job(PostgresWalArchiveJob)
  end
end
