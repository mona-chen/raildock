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

  it "re-checks destinations that never completed a probe" do
    destination(name: "pending", status: "pending", last_verified_at: nil)

    expect_any_instance_of(BackupDestinationClient).to receive(:verify!).and_return(true)

    expect(described_class.perform_now[:checked]).to eq(1)
  end

  it "checks the stalest proofs first, not the oldest rows" do
    newer_proof = destination(name: "first-row", last_verified_at: 8.days.ago)
    never = destination(name: "never", status: "failed", last_verified_at: nil)
    oldest_proof = destination(name: "oldest", last_verified_at: 60.days.ago)

    seen = []
    allow_any_instance_of(BackupDestinationClient).to receive(:verify!) do |client|
      seen << client.instance_variable_get(:@destination).name
      true
    end

    described_class.perform_now(limit: 2)

    expect(seen).to eq([ never.name, oldest_proof.name ])
    expect(seen).not_to include(newer_proof.name)
  end

  describe "outage warnings" do
    let(:organization) { create(:organization) }
    let!(:project) { create(:project, organization: organization, server: server) }
    let!(:other_project) { create(:project, organization: create(:organization), server: server) }

    def org_destination(status:)
      organization.backup_destinations.create!(
        name: "org-#{status}", provider: "s3", region: "us-east-1", bucket: "raildock-backups",
        access_key_id: "key", secret_access_key: "secret", status: status, last_verified_at: 30.days.ago
      )
    end

    it "warns the owning organization when a verified destination starts failing" do
      org_destination(status: "verified")
      allow_any_instance_of(BackupDestinationClient).to receive(:verify!).and_raise("AccessDenied")

      expect { described_class.perform_now }.to change { ActivityEvent.unscoped.count }.by(1)

      event = ActivityEvent.unscoped.last
      expect(event.project).to eq(project)
      expect(event).to be_action_warning
      expect(event.message).to include("org-verified", "stopped accepting backups")
      expect(ActivityEvent.unscoped.where(project: other_project)).to be_empty
    end

    it "does not repeat the warning for a destination that was already failing" do
      org_destination(status: "failed")
      allow_any_instance_of(BackupDestinationClient).to receive(:verify!).and_raise("AccessDenied")

      expect { described_class.perform_now }.not_to change { ActivityEvent.unscoped.count }
    end
  end
end
