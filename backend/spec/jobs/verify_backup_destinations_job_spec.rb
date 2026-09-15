require "rails_helper"

RSpec.describe VerifyBackupDestinationsJob, type: :job do
  let(:server) { create(:server) }

  def destination(name:, status: "verified", last_verified_at: Time.current)
    server.backup_destinations.create!(
      name: name,
      provider: "s3",
      region: "us-east-1",
      bucket: "raildock-backups",
      access_key_id: "key",
      secret_access_key: "secret",
      status: status,
      last_verified_at: last_verified_at
    )
  end

  it "re-verifies destinations whose proof has gone stale" do
    destination(name: "stale", last_verified_at: 30.days.ago)

    expect_any_instance_of(BackupDestinationClient).to receive(:verify!).and_return(true)

    expect(described_class.perform_now).to eq(checked: 1, failed: 0)
  end

  it "leaves freshly verified destinations alone" do
    destination(name: "fresh", last_verified_at: 1.hour.ago)

    expect_any_instance_of(BackupDestinationClient).not_to receive(:verify!)

    expect(described_class.perform_now[:checked]).to eq(0)
  end

  it "re-checks a destination that previously failed" do
    destination(name: "broken", status: "failed", last_verified_at: 30.days.ago)

    allow_any_instance_of(BackupDestinationClient).to receive(:verify!).and_raise("bucket no longer exists")

    result = described_class.perform_now

    expect(result).to eq(checked: 1, failed: 1)
  end

  it "does not touch destinations that were never configured" do
    pending_destination = destination(name: "pending", status: "pending", last_verified_at: nil)

    expect_any_instance_of(BackupDestinationClient).not_to receive(:verify!)

    described_class.perform_now
    expect(pending_destination.reload.status).to eq("pending")
  end
end
