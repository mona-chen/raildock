require "rails_helper"

RSpec.describe DataSafetyReport do
  let(:organization) { create(:organization) }
  let(:server) { create(:server, organization: organization) }
  let(:project) { create(:project, server: server) }

  def findings
    described_class.new.call[:findings]
  end

  def codes
    findings.map { |finding| finding[:code] }
  end

  it "flags a datastore that has no copy on a verified destination" do
    create(:service, :database, project: project, name: "shop-db")

    expect(codes).to include("unprotected_datastore", "no_backup_destination")
    expect(findings.find { |finding| finding[:code] == "unprotected_datastore" }[:subject]).to include(service_name: "shop-db")
    expect(described_class.new.call[:summary][:critical]).to be >= 1
  end

  it "flags mounted volumes without a snapshot" do
    service = create(:service, project: project, name: "worker")
    create(:storage_mount, :volume, service: service)

    expect(codes).to include("unprotected_volume")
  end

  it "stops flagging a datastore once a verified remote copy exists" do
    service = create(:service, :database, project: project, name: "shop-db")
    destination = server.backup_destinations.create!(
      name: "s3", provider: "s3", region: "us-east-1", bucket: "b",
      access_key_id: "a", secret_access_key: "s", status: "verified", last_verified_at: Time.current
    )
    backup = service.backups.create!(status: "completed", metadata: { "remote_verified" => true })
    backup.backup_copies.create!(backup_destination: destination, kind: :s3, status: :completed, size: 1,
      metadata: { "verified_at" => Time.current.iso8601 })

    expect(codes).not_to include("unprotected_datastore", "no_backup_destination")
  end

  it "flags destinations that have not been verified" do
    server.backup_destinations.create!(
      name: "s3", provider: "s3", region: "us-east-1", bucket: "b",
      access_key_id: "a", secret_access_key: "s", status: "failed", last_error: "bad credentials"
    )

    finding = findings.find { |candidate| candidate[:code] == "unverified_destination" }
    expect(finding[:message]).to match(/bad credentials/)
  end

  it "flags backups that only exist on this host" do
    service = create(:service, :database, project: project, name: "shop-db")
    service.backups.create!(status: "completed", file_path: "/tmp/local.dump", metadata: {})

    expect(codes).to include("local_only_backup")
  end

  it "reports backup artifacts that outlived their service" do
    create(:service, :database, project: project, name: "gone-db")
    Backup.create!(status: "completed", backup_kind: "database",
      metadata: { "service_name" => "gone-db", "project_name" => project.name, "remote_verified" => true })

    finding = findings.find { |candidate| candidate[:code] == "detached_backup" }
    expect(finding[:severity]).to eq("info")
    expect(finding[:message]).to include("gone-db")
  end

  it "scopes the report to a single organization" do
    other_server = create(:server)
    create(:service, :database, project: create(:project, server: other_server), name: "other-db")
    local = create(:service, :database, project: project, name: "shop-db")

    report = described_class.new(organization: organization).call

    expect(report[:findings].map { |finding| finding.dig(:subject, :service_name) }).to include(local.name)
    expect(report[:findings].map { |finding| finding.dig(:subject, :service_name) }).not_to include("other-db")
  end

  describe "point-in-time recovery" do
    def pitr_config(service, status:, last_wal_archived_at: nil, last_error: nil)
      destination = server.backup_destinations.create!(
        name: "pitr-#{service.name}", provider: "s3", region: "us-east-1", bucket: "b",
        access_key_id: "a", secret_access_key: "s", status: "verified", last_verified_at: Time.current
      )
      service.create_postgres_pitr_config!(
        backup_destination: destination,
        retention_days: 7,
        enabled: status == "active",
        status: status,
        last_wal_archived_at: last_wal_archived_at,
        last_error: last_error
      )
    end

    it "is critical when WAL archiving is failing" do
      service = create(:service, :database, project: project, subtype: "postgres", name: "pay-db")
      pitr_config(service, status: "error", last_error: "S3 upload denied")

      finding = findings.find { |candidate| candidate[:code] == "pitr_archive_failed" }
      expect(finding[:severity]).to eq("critical")
      expect(finding[:message]).to include("S3 upload denied")
      expect(finding[:subject]).to include(service_name: "pay-db")
    end

    it "warns when archiving has stalled even though the config looks active" do
      service = create(:service, :database, project: project, subtype: "postgres", name: "pay-db")
      pitr_config(service, status: "active", last_wal_archived_at: 5.hours.ago)

      expect(codes).to include("pitr_archive_stalled")
    end

    it "stays quiet while segments are flowing" do
      service = create(:service, :database, project: project, subtype: "postgres", name: "pay-db")
      pitr_config(service, status: "active", last_wal_archived_at: 5.minutes.ago)

      expect(codes).not_to include("pitr_archive_failed", "pitr_archive_stalled")
    end
  end
end
