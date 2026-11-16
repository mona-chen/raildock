require "rails_helper"

RSpec.describe "Network flows", type: :request do
  let(:user) { create(:user) }
  let(:organization) { create(:organization, owner: user) }
  let!(:membership) { create(:organization_membership, user: user, organization: organization, role: :owner) }
  let(:server) { create(:server, organization: organization) }
  let(:project) { create(:project, server: server, organization: organization) }
  let(:source) { create(:service, project: project) }
  let(:target) { create(:service, project: project) }
  let!(:link) { ServiceLink.create!(from_service: source, to_service: target) }
  let(:headers) { auth_headers(user).merge("X-Organization-ID" => organization.id.to_s, "Content-Type" => "application/json") }

  it "defaults to off and performs no SSH collection" do
    expect(NetworkFlowSamplerJob).not_to receive(:perform_later)
    get "/api/projects/#{project.id}/network_flows", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include("enabled" => false)
    expect(response.parsed_body["links"].first["state"]).to eq("disabled")
  end

  it "validates policy and forbids foreign servers and ordinary members" do
    patch "/api/servers/#{server.id}/network_flow_settings", params: { settings: { enabled: true, retention_days: 100 } }.to_json, headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
    membership.update!(role: :member)
    patch "/api/servers/#{server.id}/network_flow_settings", params: { settings: { enabled: true, retention_days: 0 } }.to_json, headers: headers
    expect(response).to have_http_status(:forbidden)
    membership.update!(role: :owner)
    get "/api/servers/#{create(:server).id}/network_flow_settings", headers: headers
    expect(response).to have_http_status(:not_found)
  end

  it "does not present stale traffic as current activity" do
    server.update!(network_flow_settings: { "enabled" => true }, network_flow_snapshot: { "sampled_at" => 1.minute.ago.iso8601, "links" => [ { "id" => link.id.to_s, "state" => "sampled", "sent_bytes" => 1000 } ] })
    get "/api/projects/#{project.id}/network_flows", headers: headers
    expect(response.parsed_body["links"].first["state"]).to eq("unavailable")
  end

  it "isolates environments and projects even though collection is batched per host" do
    other = create(:project, server: server, organization: organization)
    foreign_link = ServiceLink.create!(from_service: create(:service, project: other), to_service: create(:service, project: other))
    staging = project.environments.create!(name: "staging")
    staging_link = ServiceLink.create!(from_service: create(:service, project: project, environment: staging), to_service: create(:service, project: project, environment: staging))
    get "/api/projects/#{project.id}/network_flows", headers: headers
    expect(response.parsed_body["links"].map { |row| row["id"] }).to eq([ link.id.to_s ])
    get "/api/projects/#{project.id}/network_flows?environment_id=#{staging.id}", headers: headers
    expect(response.parsed_body["links"].map { |row| row["id"] }).to eq([ staging_link.id.to_s ])
    get "/api/projects/#{project.id}/network_flows/#{foreign_link.id}/history", headers: headers
    expect(response).to have_http_status(:not_found)
  end
end
