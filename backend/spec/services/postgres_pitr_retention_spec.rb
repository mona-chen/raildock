require "rails_helper"

RSpec.describe PostgresPitrRetention do
  let(:service) { create(:service, :database) }
  let(:destination) { service.project.server.backup_destinations.create!(name: "offsite", provider: "s3", bucket: "test", region: "auto") }
  let(:config) { service.create_postgres_pitr_config!(backup_destination: destination, retention_days: 7) }
  def artifact(kind, age, metadata = {})
    service.backups.create!(status: "completed", backup_kind: kind, metadata: metadata, created_at: age.ago)
  end
  it "keeps every WAL segment since the base anchoring the retention window" do
    obsolete = artifact("pitr_base", 10.days)
    old_wal = artifact("wal", 9.days)
    anchor = artifact("pitr_base", 8.days)
    required = artifact("wal", 7.days + 6.hours)
    newest = artifact("pitr_base", 1.day)
    described_class.new(config).prune!
    expect(service.backups.pluck(:id)).to include(anchor.id, required.id, newest.id)
    expect(service.backups.pluck(:id)).not_to include(obsolete.id, old_wal.id)
  end
  it "preserves the entire remaining chain when archiving has stalled beyond the window" do
    base = artifact("pitr_base", 12.days)
    wal = artifact("wal", 11.days)
    described_class.new(config).prune!
    expect(service.backups.pluck(:id)).to include(base.id, wal.id)
  end
  it "keeps timeline history even when it predates the retained base" do
    history = artifact("wal", 20.days, "wal_name" => "00000002.history")
    artifact("pitr_base", 8.days)
    described_class.new(config).prune!
    expect(Backup.exists?(history.id)).to be(true)
  end
end
