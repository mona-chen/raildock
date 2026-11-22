require "rails_helper"

RSpec.describe "PITR recovery into a new service", type: :request do
  let(:user) { create(:user, :admin) }
  let(:server) { create(:server) }
  let(:project) { create(:project, server: server) }
  let(:service) { create(:service, :database, project: project, subtype: "postgres", name: "main-db") }
  let(:headers) { auth_headers(user) }
  let(:destination) do
    server.backup_destinations.create!(name: "S3", provider: "s3", region: "us-east-1", bucket: "recovery",
      access_key_id: "access", secret_access_key: "secret", status: "verified")
  end
  let!(:base) { service.backups.create!(backup_kind: "pitr_base", status: "completed", created_at: 2.hours.ago) }
  let!(:wal) do
    service.backups.create!(backup_kind: "wal", status: "completed", created_at: 5.minutes.ago,
      metadata: { "wal_name" => "000000010000000000000003" })
  end
  let(:path) { "/api/services/#{service.id}/recovery/pitr/restore" }

  before do
    service.create_postgres_pitr_config!(backup_destination: destination, retention_days: 7)
    allow(PitrRestoreJob).to receive(:perform_later)
  end

  it "stages a new service in the same environment and queues the recovery without touching the live database" do
    expect(DokkuEngine).not_to receive(:new)
    expect(HostEngine).not_to receive(:new)
    target = 1.hour.ago.change(usec: 0)

    post path, headers: headers, params: { target_time: target.iso8601, name: "main-db-restored" }, as: :json

    expect(response).to have_http_status(:accepted)
    restore = PitrRestore.last
    restored = restore.restored_service
    expect(restored).to have_attributes(name: "main-db-restored", subtype: "postgres", status: "deploying",
      environment_id: service.environment_id, project_id: project.id)
    expect(restored.dokku_app_name).not_to eq(service.dokku_app_name)
    expect(restore).to have_attributes(source_service_id: service.id, backup_id: base.id, status: "pending", target_time: target)
    expect(PitrRestoreJob).to have_received(:perform_later).with(restore.id)
    expect(response.parsed_body.dig("service", "name")).to eq("main-db-restored")
  end

  it "lists the restores in the recovery overview" do
    post path, headers: headers, params: { target_time: 1.hour.ago.iso8601, name: "copy" }, as: :json

    get "/api/services/#{service.id}/recovery", headers: headers

    expect(response.parsed_body["pitr_restores"].first).to include("restored_service_name" => "copy", "status" => "pending")
  end

  it "refuses a moment before the oldest base backup" do
    post path, headers: headers, params: { target_time: 3.hours.ago.iso8601, name: "copy" }, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body["code"]).to eq("outside_window")
    expect(Service.where(name: "copy")).to be_empty
  end

  it "refuses a moment after the last archived WAL" do
    post path, headers: headers, params: { target_time: 1.minute.ago.iso8601, name: "copy" }, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body["code"]).to eq("outside_window")
  end

  it "refuses a name already used in the environment" do
    post path, headers: headers, params: { target_time: 1.hour.ago.iso8601, name: "MAIN-DB" }, as: :json

    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body["code"]).to eq("name_taken")
  end

  it "refuses a second recovery while one is running" do
    post path, headers: headers, params: { target_time: 1.hour.ago.iso8601, name: "copy-1" }, as: :json
    post path, headers: headers, params: { target_time: 1.hour.ago.iso8601, name: "copy-2" }, as: :json

    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body["code"]).to eq("restore_in_progress")
  end

  it "refuses when PITR is not enabled" do
    service.postgres_pitr_config.destroy!

    post path, headers: headers, params: { target_time: 1.hour.ago.iso8601, name: "copy" }, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body["code"]).to eq("pitr_disabled")
  end

  context "as a member (no update permission)" do
    let(:organization) { create(:organization) }
    let(:project) { create(:project, server: server, organization: organization) }
    let(:user) { create(:user, admin: false).tap { |member| organization.memberships.create!(user: member, role: :member) } }
    let(:headers) { auth_headers(user).merge("X-Organization-ID" => organization.id.to_s) }

    it "is forbidden and creates nothing" do
      post path, headers: headers, params: { target_time: 1.hour.ago.iso8601, name: "copy" }, as: :json

      expect(response).to have_http_status(:forbidden)
      expect(PitrRestore.count).to eq(0)
      expect(PitrRestoreJob).not_to have_received(:perform_later)
    end
  end
end
