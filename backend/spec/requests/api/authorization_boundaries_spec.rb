require "rails_helper"

RSpec.describe "Authorization boundaries", type: :request do
  let(:owner) { create(:user, admin: false) }
  let(:organization) { create(:organization, owner: owner) }
  let(:project) { create(:project, organization: organization, server: nil, shared_vars: [ { key: "SECRET", value: "private" } ]) }
  let(:outsider) { create(:user, admin: false) }
  let(:member) do
    create(:user, admin: false).tap { |user| organization.memberships.create!(user: user, role: :member) }
  end
  def headers(user)
    auth_headers(user).merge("X-Organization-ID" => organization.id.to_s)
  end

  it "refuses a forged organization context without exposing variables or writing projects" do
    project
    get "/api/projects", headers: headers(outsider)
    expect(response).to have_http_status(:forbidden)
    expect(response.body).not_to include("private")
    expect { post "/api/projects", params: { name: "injected" }, headers: headers(outsider) }.not_to change(Project, :count)
    expect(response).to have_http_status(:forbidden)
  end

  it "refuses an invalid organization rather than falling back to a personal context" do
    get "/api/projects", headers: auth_headers(outsider).merge("X-Organization-ID" => "99999999")
    expect(response).to have_http_status(:forbidden)
  end

  it "halts an action-level denial before persisting the service or touching Dokku" do
    service = create(:service, project: project)
    expect(DokkuEngine).not_to receive(:new)
    patch "/api/services/#{service.id}", params: { name: "forbidden" }, headers: headers(member)
    expect(response).to have_http_status(:forbidden)
    expect(service.reload.name).not_to eq("forbidden")
  end

  it "allows member reads but forbids configuration and storage writes" do
    service = create(:service, project: project)
    get "/api/services/#{service.id}", headers: headers(member)
    expect(response).to have_http_status(:ok)
    expect { post "/api/services/#{service.id}/env-vars", params: { key: "X", value: "Y" }, headers: headers(member) }.not_to change(EnvironmentVariable, :count)
    expect(response).to have_http_status(:forbidden)
    expect { post "/api/services/#{service.id}/storage", params: { container_path: "/data", kind: "volume" }, headers: headers(member) }.not_to change(StorageMount, :count)
    expect(response).to have_http_status(:forbidden)
  end

  it "does not let an org admin create an owner membership" do
    admin = create(:user, admin: false)
    organization.memberships.create!(user: admin, role: :admin)
    target = create(:user, admin: false)
    expect { post "/api/organizations/#{organization.id}/members", params: { email: target.email, role: "owner" }, headers: headers(admin) }.not_to change(OrganizationMembership, :count)
    expect(response).to have_http_status(:forbidden)
  end

  it "limits bulk deployments to the requested environment and defaults to production" do
    organization.memberships.create!(user: owner, role: :owner)
    staging = project.environments.create!(name: "staging")
    production_app = create(:service, project: project)
    staged_app = create(:service, project: project, environment: staging, status: :stopped)
    allow(DeploymentSequenceJob).to receive(:perform_later)
    post "/api/projects/#{project.id}/deploy_all", params: { environment_id: staging.id }, headers: headers(owner)
    expect(response).to have_http_status(:ok)
    expect(staged_app.deployments.count).to eq(1)
    expect(production_app.deployments.count).to eq(0)
    post "/api/projects/#{project.id}/deploy_all", headers: headers(owner)
    expect(production_app.deployments.count).to eq(1)
    expect(staged_app.deployments.count).to eq(1)
  end
end
