require "rails_helper"

RSpec.describe "Api::EnvironmentsController", type: :request do
  let(:user) { create(:user) }
  let(:project) { create(:project) }
  let!(:service) { create(:service, project: project) }

  describe "GET /api/projects/:project_id/environments" do
    it "returns 401 when unauthenticated" do
      get "/api/projects/#{project.id}/environments"

      expect(response).to have_http_status(:unauthorized)
    end

    it "lists the default environment with its services" do
      get "/api/projects/#{project.id}/environments", headers: auth_headers(user)

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json.length).to eq(1)
      expect(json.first["name"]).to eq("production")
      expect(json.first["is_default"]).to be(true)
      expect(json.first["service_ids"]).to eq([ service.id ])
      expect(json.first["service_count"]).to eq(1)
    end
  end

  describe "POST /api/projects/:project_id/environments" do
    it "creates an environment with a slugified name" do
      post "/api/projects/#{project.id}/environments",
        params: { environment: { name: "QA Sandbox" } },
        headers: auth_headers(user),
        as: :json

      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json["name"]).to eq("QA Sandbox")
      expect(json["slug"]).to eq("qa-sandbox")
      expect(json["is_default"]).to be(false)
    end

    it "rejects a blank name" do
      post "/api/projects/#{project.id}/environments",
        params: { environment: { name: "" } },
        headers: auth_headers(user),
        as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "PATCH /api/projects/:project_id/environments/:id" do
    it "renames a non-default environment" do
      staging = project.environments.create!(name: "staging")

      patch "/api/projects/#{project.id}/environments/#{staging.id}",
        params: { environment: { name: "qa" } },
        headers: auth_headers(user),
        as: :json

      expect(response).to have_http_status(:ok)
      expect(staging.reload.name).to eq("qa")
      expect(staging.slug).to eq("qa")
      # A non-default rename must not relabel the project's primary environment.
      expect(project.reload.environment).to eq("production")
    end

    it "keeps the project's primary label in sync when the default is renamed" do
      default = project.default_environment

      patch "/api/projects/#{project.id}/environments/#{default.id}",
        params: { environment: { name: "prod" } },
        headers: auth_headers(user),
        as: :json

      expect(response).to have_http_status(:ok)
      expect(project.reload.environment).to eq("prod")
    end
  end

  describe "DELETE /api/projects/:project_id/environments/:id" do
    it "refuses to delete the default environment" do
      default = project.default_environment

      delete "/api/projects/#{project.id}/environments/#{default.id}", headers: auth_headers(user)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["code"]).to eq("environment_guarded")
      expect(project.environments.reload).to include(default)
    end

    it "refuses to delete an environment that still owns services" do
      staging = project.environments.create!(name: "staging")
      create(:service, project: project, environment: staging)

      delete "/api/projects/#{project.id}/environments/#{staging.id}", headers: auth_headers(user)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(Environment.exists?(staging.id)).to be(true)
    end

    it "deletes an empty environment" do
      staging = project.environments.create!(name: "staging")

      expect {
        delete "/api/projects/#{project.id}/environments/#{staging.id}", headers: auth_headers(user)
      }.to change(Environment, :count).by(-1)

      expect(response).to have_http_status(:no_content)
    end
  end

  describe "project payload" do
    it "exposes environments as a first-class key" do
      project.environments.create!(name: "staging")

      get "/api/projects/#{project.id}", headers: auth_headers(user)

      json = JSON.parse(response.body)
      expect(json["environments"].map { |environment| environment["name"] }).to eq(%w[production staging])
      expect(json["has_deployments"]).to be(false)
    end
  end
end
