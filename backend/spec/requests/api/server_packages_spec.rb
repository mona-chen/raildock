require "rails_helper"

RSpec.describe "Server package maintenance", type: :request do
  let(:user) { create(:user) }
  let(:organization) { create(:organization, owner: user) }
  let!(:membership) { create(:organization_membership, organization: organization, user: user, role: :owner) }
  let(:server) { create(:server, organization: organization) }
  let(:headers) { auth_headers(user).merge("X-Organization-ID" => organization.id.to_s) }

  it "reads cached state without SSH" do
    expect(HostEngine).not_to receive(:new)
    get "/api/servers/#{server.id}/packages", headers: headers
    expect(response).to have_http_status(:ok)
  end

  it "rejects foreign servers" do
    get "/api/servers/#{create(:server).id}/packages", headers: headers
    expect(response).to have_http_status(:not_found)
  end

  it "does not permit members to start host operations" do
    membership.update!(role: :member)
    expect(ServerPackageManager).not_to receive(:start)
    post "/api/servers/#{server.id}/packages", params: { kind: "check" }, headers: headers
    expect(response).to have_http_status(:forbidden)
  end

  it "requires the exact server name and disruption acknowledgement before installing" do
    expect(ServerPackageManager).not_to receive(:start)
    post "/api/servers/#{server.id}/packages", params: { kind: "install", confirmation: "wrong", acknowledge_disruption: true }.to_json, headers: headers.merge("Content-Type" => "application/json")
    expect(response).to have_http_status(:precondition_required)
  end

  it "queues a check and audits it without running SSH inside the request" do
    expect(ServerPackageUpdateJob).to receive(:perform_later)
    expect(HostEngine).not_to receive(:new)
    post "/api/servers/#{server.id}/packages", params: { kind: "check" }, headers: headers
    expect(response).to have_http_status(:accepted)
    expect(server.reload.package_updates.dig("operation", "status")).to eq("scheduled")
  end
end
