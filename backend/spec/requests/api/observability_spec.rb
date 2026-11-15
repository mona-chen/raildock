require "rails_helper"
RSpec.describe "Observability", type: :request do
  let(:user) { create(:user) }
  let(:organization) { create(:organization, owner: user) }
  let!(:membership) { create(:organization_membership, user: user, organization: organization, role: :owner) }
  let(:server) { create(:server, organization: organization) }
  let(:headers) { auth_headers(user).merge("X-Organization-ID" => organization.id.to_s) }
  it "saves organization notification settings and refuses invalid thresholds" do
    patch "/api/notifications", params: { settings: { enabled: true, cpu: 95 } }.to_json, headers: headers.merge("Content-Type" => "application/json")
    expect(response).to have_http_status(:ok)
    expect(organization.reload.notification_settings["cpu"]).to eq(95)
    patch "/api/notifications", params: { settings: { window_minutes: 0 } }.to_json, headers: headers.merge("Content-Type" => "application/json")
    expect(response).to have_http_status(:unprocessable_entity)
  end
  it "validates additional email destinations without changing existing policy on failure" do
    patch "/api/notifications", params: { settings: { email_destinations: [ "ops@example.test", "oncall@example.test" ] } }.to_json, headers: headers.merge("Content-Type" => "application/json")
    expect(response).to have_http_status(:ok)
    expect(organization.reload.notification_settings["email_destinations"]).to eq([ "ops@example.test", "oncall@example.test" ])
    patch "/api/notifications", params: { settings: { email_destinations: [ "bad\nBcc: attacker@example.test" ] } }.to_json, headers: headers.merge("Content-Type" => "application/json")
    expect(response).to have_http_status(:unprocessable_entity)
    expect(organization.reload.notification_settings["email_destinations"]).to eq([ "ops@example.test", "oncall@example.test" ])
  end
  it "forbids members and isolates incidents from other organizations" do
    membership.update!(role: :member)
    get "/api/notifications", headers: headers
    expect(response).to have_http_status(:forbidden)
    membership.update!(role: :owner)
    foreign = create(:server)
    foreign.monitoring_incidents.create!(signal: "cpu", state: "firing", started_at: Time.current, last_seen_at: Time.current, message: "private")
    get "/api/notifications", headers: headers
    expect(response.parsed_body["incidents"]).to be_empty
    get "/api/servers/#{foreign.id}/traffic", headers: headers
    expect(response).to have_http_status(:not_found)
  end
  it "rejects unsupported paths and persists collection settings" do
    patch "/api/servers/#{server.id}/traffic", params: { settings: { enabled: true, path: "/etc/shadow", format: "caddy", retention_days: 7 } }.to_json, headers: headers.merge("Content-Type" => "application/json")
    expect(response).to have_http_status(:unprocessable_entity)
    patch "/api/servers/#{server.id}/traffic", params: { settings: { enabled: true, path: "/var/log/caddy/access.log", format: "caddy", retention_days: 7 } }.to_json, headers: headers.merge("Content-Type" => "application/json")
    expect(response).to have_http_status(:ok)
    expect(server.reload.traffic_settings["enabled"]).to be(true)
  end
  it "merges histogram counts rather than averaging percentiles, preserving path spelling" do
    2.times do |index|
      server.http_traffic_buckets.create!(bucket_at: (index + 1).minutes.ago.beginning_of_minute, data: { "unmapped" => { "requests" => 10, "histogram" => [ 1, 9 ], "paths" => { "/my_path" => 10 } } })
    end
    get "/api/servers/#{server.id}/traffic?hours=1", headers: headers
    expect(response.parsed_body["summary"]["requests"]).to eq(20)
    expect(response.parsed_body["summary"]["histogram"].first(2)).to eq([ 2, 18 ])
    expect(response.parsed_body["summary"]["paths"]).to eq([ { "path" => "/my_path", "count" => 20 } ])
  end
  it "requires an authorized, valid review before scheduling proxy changes" do
    post "/api/servers/#{server.id}/traffic/setup", params: { review_token: "invalid" }.to_json, headers: headers.merge("Content-Type" => "application/json")
    expect(response).to have_http_status(:unprocessable_entity)
    expect(server.reload.traffic_settings).not_to include("setup_state")
    membership.update!(role: :member)
    expect(HttpTrafficSetup).not_to receive(:new)
    get "/api/servers/#{server.id}/traffic/setup", headers: headers
    expect(response).to have_http_status(:forbidden)
  end
end
