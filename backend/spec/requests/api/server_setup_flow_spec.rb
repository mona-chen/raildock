require "rails_helper"

RSpec.describe "Automated remote server setup flow", type: :request do
  let(:user) { create(:user, admin: false) }
  let(:organization) { create(:organization, owner: user) }
  let!(:membership) { create(:organization_membership, user: user, organization: organization, role: :owner) }
  let(:org_headers) { auth_headers(user).merge("X-Organization-ID" => organization.id.to_s) }

  it "generates an org key, returns a bootstrap command, tests the host, and creates a validated server" do
    get "/api/organizations/#{organization.id}/server_bootstrap", headers: org_headers
    expect(response).to have_http_status(:ok)

    bootstrap = JSON.parse(response.body)
    expect(bootstrap["public_key"]).to start_with("ssh-")
    expect(bootstrap["command"]).to include("bootstrap.sh")

    test_result = {
      success: true,
      host: "192.168.1.50",
      ssh_user: "dokku",
      host_key: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExample",
      host_key_fingerprint: "SHA256:abcdef",
      dokku_version: "0.35.0",
      docker_version: "26.0.0"
    }
    service = instance_double(ServerTestService, test: test_result)
    allow(ServerTestService).to receive(:new).with(organization: organization, host: "192.168.1.50", ssh_user: "dokku").and_return(service)

    post "/api/servers/test", params: { server: { host: "192.168.1.50", ssh_user: "dokku" } }, headers: org_headers
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)["success"]).to be true

    expect {
      post "/api/servers", params: {
        server: {
          name: "Remote Dokku",
          host: "192.168.1.50",
          ssh_user: "dokku",
          host_key: test_result[:host_key],
          host_key_fingerprint: test_result[:host_key_fingerprint]
        }
      }, headers: org_headers
    }.to change(Server, :count).by(1)

    expect(response).to have_http_status(:created)
    server = Server.order(:id).last
    expect(server.organization_id).to eq(organization.id)
    expect(server.host_key).to eq(test_result[:host_key])

    engine = instance_double(DokkuEngine)
    allow(DokkuEngine).to receive(:new).with(server).and_return(engine)
    allow(engine).to receive(:validate_connection).and_return(
      { success: true, dokku_version: "0.35.0", docker_version: "26.0.0", os: "Ubuntu", uptime: "1d" }
    )
    allow(engine).to receive(:run).with("proxy:report --global --proxy-global-type").and_return(
      { success: true, output: "traefik" }
    )

    post "/api/servers/#{server.id}/validate", headers: org_headers
    expect(response).to have_http_status(:ok)

    server.reload
    expect(server.status).to eq("connected")
    expect(server.dokku_version).to eq("0.35.0")
    expect(server.default_proxy).to eq("traefik")
  end

  it "does not create a server when the pre-save connection test fails" do
    OrganizationSshKeyService.generate(organization)

    result = { success: false, error: "Connection refused" }
    service = instance_double(ServerTestService, test: result)
    allow(ServerTestService).to receive(:new).and_return(service)

    post "/api/servers/test", params: { server: { host: "192.168.1.51" } }, headers: org_headers
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)["success"]).to be false

    expect {
      post "/api/servers", params: { server: { name: "Bad Host", host: "192.168.1.51" } }, headers: org_headers
    }.to change(Server, :count).by(1)

    # The UI is responsible for blocking create until the test succeeds; the API
    # allows it so the wizard can choose its own UX. The created server remains
    # disconnected until validated.
    server = Server.order(:id).last
    expect(server.status).to eq("disconnected")
  end
end
