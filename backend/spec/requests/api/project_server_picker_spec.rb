require "rails_helper"

RSpec.describe "POST /api/projects server selection", type: :request do
  let(:user) { create(:user, admin: false) }
  let(:organization) { create(:organization, owner: user) }
  let!(:membership) { create(:organization_membership, user: user, organization: organization, role: :owner) }
  let(:headers) { auth_headers(user).merge("X-Organization-ID" => organization.id.to_s) }

  it "uses the server the user picked" do
    create(:server, organization: organization, status: :connected)
    picked = create(:server, organization: organization, status: :connected)

    post "/api/projects", params: { project: { name: "picked", server_id: picked.id } }, headers: headers

    expect(response).to have_http_status(:created)
    expect(Project.find(response.parsed_body["id"]).server).to eq(picked)
  end

  it "defaults to a connected server rather than the first one" do
    create(:server, organization: organization, status: :error)
    healthy = create(:server, organization: organization, status: :connected)

    post "/api/projects", params: { project: { name: "default" } }, headers: headers

    expect(response).to have_http_status(:created)
    expect(Project.find(response.parsed_body["id"]).server).to eq(healthy)
  end

  it "refuses a server from another organization instead of silently using a different one" do
    create(:server, organization: organization)
    foreign = create(:server)

    expect {
      post "/api/projects", params: { project: { name: "x", server_id: foreign.id } }, headers: headers
    }.not_to change(Project, :count)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body["code"]).to eq("invalid_server")
  end

  it "never defaults an instance admin to another organization's server" do
    admin = create(:user, :admin)
    create(:organization_membership, user: admin, organization: organization, role: :owner)
    create(:server, status: :connected) # another organization's
    own = create(:server, organization: organization, status: :disconnected)

    post "/api/projects", params: { project: { name: "admin" } },
         headers: auth_headers(admin).merge("X-Organization-ID" => organization.id.to_s)

    expect(response).to have_http_status(:created)
    expect(Project.find(response.parsed_body["id"]).server).to eq(own)
  end
end
