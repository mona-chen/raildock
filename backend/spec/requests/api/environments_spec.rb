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

  describe "POST /api/projects/:project_id/environments/:id/duplicate" do
    it "copies every service into a new environment and reports the staging summary" do
      source = project.default_environment
      create(:service, project: project, environment: source, name: "web", branch: "main")
      source_service_count = source.services.count

      expect {
        post "/api/projects/#{project.id}/environments/#{source.id}/duplicate",
          params: { environment: { name: "staging" } },
          headers: auth_headers(user),
          as: :json
      }.to change { project.environments.count }.by(1)

      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      staging = project.environments.find_by(name: "staging")
      expect(json["environment"]["name"]).to eq("staging")
      expect(json["summary"]["services"]).to eq(source_service_count)
      expect(staging.services.count).to eq(source_service_count)
      expect(staging.services.find_by(name: "web")).to be_stopped
    end

    it "rejects a blank name without creating an environment" do
      source = project.default_environment

      expect {
        post "/api/projects/#{project.id}/environments/#{source.id}/duplicate",
          params: { environment: { name: "" } },
          headers: auth_headers(user),
          as: :json
      }.not_to change { project.environments.count }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["code"]).to eq("name_required")
    end

    it "rejects a name another environment already uses" do
      source = project.default_environment
      project.environments.create!(name: "staging")

      post "/api/projects/#{project.id}/environments/#{source.id}/duplicate",
        params: { environment: { name: "staging" } },
        headers: auth_headers(user),
        as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["code"]).to eq("invalid_environment")
    end

    it "requires authentication" do
      source = project.default_environment

      post "/api/projects/#{project.id}/environments/#{source.id}/duplicate",
        params: { environment: { name: "staging" } },
        as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/projects/:project_id/environments/:id/sync_plan" do
    it "reports what a sync would add" do
      source = project.default_environment
      staging = project.environments.create!(name: "staging")
      create(:service, project: project, environment: source, name: "web")

      get "/api/projects/#{project.id}/environments/#{staging.id}/sync_plan",
        params: { source_environment_id: source.id },
        headers: auth_headers(user)

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["added"].map { |entry| entry["name"] }).to include("web")
      expect(json["summary"]["in_sync"]).to be(false)
      expect(staging.services.reload).to be_empty
    end

    it "refuses an environment from another project" do
      source = project.default_environment
      staging = project.environments.create!(name: "staging")
      other = create(:project)

      get "/api/projects/#{project.id}/environments/#{staging.id}/sync_plan",
        params: { source_environment_id: other.default_environment.id },
        headers: auth_headers(user)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["code"]).to eq("invalid_source_environment")
    end

    it "refuses to sync an environment with itself" do
      staging = project.environments.create!(name: "staging")

      get "/api/projects/#{project.id}/environments/#{staging.id}/sync_plan",
        params: { source_environment_id: staging.id },
        headers: auth_headers(user)

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "POST /api/projects/:project_id/environments/:id/sync" do
    it "adds the missing services and reports what it left alone" do
      source = project.default_environment
      staging = project.environments.create!(name: "staging")
      create(:service, project: project, environment: source, name: "web")
      create(:service, project: project, environment: staging, name: "staging-only")

      post "/api/projects/#{project.id}/environments/#{staging.id}/sync",
        params: { source_environment_id: source.id },
        headers: auth_headers(user),
        as: :json

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["applied"]["added"].map { |service| service["name"] }).to include("web")
      expect(json["applied"]["removed"].map { |service| service["name"] }).to eq([ "staging-only" ])
      expect(staging.services.reload.map(&:name)).to include("web", "staging-only")
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
