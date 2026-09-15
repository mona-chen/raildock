require "rails_helper"

RSpec.describe BackupRetention, type: :service do
  let(:service) { create(:service, :database, subtype: "postgres") }

  def create_backup(kind: "database", age_minutes: 0, trigger: nil, schedule_id: nil)
    backup = service.backups.create!(
      status: "completed",
      backup_kind: kind,
      metadata: { "trigger" => trigger, "schedule_id" => schedule_id }.compact
    )
    backup.update_column(:created_at, age_minutes.minutes.ago)
    backup
  end

  def prune(keep:, scope: service.backups.completed)
    described_class.prune(scope, keep: keep)
  end

  it "expires everything past the newest `keep` artifacts" do
    newest = create_backup(age_minutes: 1, schedule_id: 1)
    middle = create_backup(age_minutes: 2, schedule_id: 1)
    oldest = create_backup(age_minutes: 3, schedule_id: 1)

    result = prune(keep: 2)

    expect(result.removed).to eq(1)
    expect(Backup.exists?(newest.id)).to be(true)
    expect(Backup.exists?(middle.id)).to be(true)
    expect(Backup.exists?(oldest.id)).to be(false)
  end

  it "never expires the newest artifact of a kind that stopped being captured" do
    fresh = create_backup(age_minutes: 1)
    create_backup(age_minutes: 2)
    only_volume_snapshot = create_backup(kind: "volume", age_minutes: 3)

    prune(keep: 2)

    expect(Backup.exists?(fresh.id)).to be(true)
    expect(Backup.exists?(only_volume_snapshot.id)).to be(true)
  end

  it "never expires a pre-destroy safety snapshot" do
    live = create_backup(age_minutes: 1)
    safety_net = create_backup(age_minutes: 10, trigger: "pre_destroy")
    create_backup(age_minutes: 5)

    described_class.prune(service.backups.completed, keep: 1)

    expect(Backup.exists?(live.id)).to be(true)
    expect(Backup.exists?(safety_net.id)).to be(true)
  end

  it "never expires a pre-restore safety snapshot" do
    safety_net = create_backup(age_minutes: 30, trigger: "pre_restore")
    create_backup(age_minutes: 1)
    create_backup(age_minutes: 2)

    described_class.prune(service.backups.completed, keep: 1)

    expect(Backup.exists?(safety_net.id)).to be(true)
  end

  it "always keeps at least one artifact even when asked to keep none" do
    newest = create_backup(age_minutes: 1)
    create_backup(age_minutes: 2)

    prune(keep: 0)

    expect(Backup.exists?(newest.id)).to be(true)
    expect(service.backups.completed.count).to eq(1)
  end

  it "keeps the only artifact of a service rather than emptying it" do
    only = create_backup(age_minutes: 100)

    expect { prune(keep: 3) }.not_to change { service.backups.completed.count }
    expect(Backup.exists?(only.id)).to be(true)
  end

  it "only expires artifacts inside the scope it is given" do
    in_scope = create_backup(age_minutes: 1, schedule_id: 7)
    old_in_scope = create_backup(age_minutes: 2, schedule_id: 7)
    other_schedule = create_backup(age_minutes: 50, schedule_id: 99)

    described_class.prune(service.backups.completed.where("metadata->>'schedule_id' = ?", "7"), keep: 1)

    expect(Backup.exists?(in_scope.id)).to be(true)
    expect(Backup.exists?(old_in_scope.id)).to be(false)
    expect(Backup.exists?(other_schedule.id)).to be(true)
  end
end
