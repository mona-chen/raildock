require "rails_helper"

RSpec.describe "Api::ManifestsController", type: :request do
  let(:user) { create(:user) }
  let(:server) { create(:server) }
  let(:project) { create(:project, server: server) }

  describe "PATCH /api/projects/:project_id/manifest" do
    context "auto-detecting format from raw content" do
      it "detects railway.toml from [build] section" do
        body = <<~TOML
          [build]
          builder = "railpack"

          [deploy]
          startCommand = "npm start"
        TOML

        patch "/api/projects/#{project.id}/manifest",
              params: { manifest: { content: body } },
              headers: auth_headers(user),
              as: :json

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["format"]).to eq("railway.toml")
      end

      it "detects railway.json from build key" do
        body = <<~JSON
          {
            "build": { "builder": "railpack" },
            "deploy": { "startCommand": "npm start" }
          }
        JSON

        patch "/api/projects/#{project.id}/manifest",
              params: { manifest: { content: body } },
              headers: auth_headers(user),
              as: :json

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["format"]).to eq("railway.json")
      end

      it "still detects app.json when buildpacks is present" do
        body = <<~JSON
          {
            "name": "my-app",
            "buildpacks": ["heroku/ruby"],
            "env": {}
          }
        JSON

        patch "/api/projects/#{project.id}/manifest",
              params: { manifest: { content: body } },
              headers: auth_headers(user),
              as: :json

        json = JSON.parse(response.body)
        expect(json["format"]).to eq("app.json")
      end

      it "still detects raildock.toml for the default case" do
        body = <<~TOML
          [[services]]
          name = "api"
          category = "app"
          subtype = "web"
        TOML

        patch "/api/projects/#{project.id}/manifest",
              params: { manifest: { content: body } },
              headers: auth_headers(user),
              as: :json

        json = JSON.parse(response.body)
        expect(json["format"]).to eq("raildock.toml")
      end
    end
  end

  describe "POST /api/projects/:project_id/manifest/apply" do
    let(:manifest) do
      <<~TOML
        [[services]]
        name = "web"
        category = "app"
        subtype = "web"
      TOML
    end

    before do
      project.update!(manifest_content: manifest, manifest_format: "raildock.toml")
      create(:service, project: project, name: "old-worker", managed_by: :manifest)
    end

    it "refuses to destroy services until the removals are confirmed" do
      expect {
        post "/api/projects/#{project.id}/manifest/apply", headers: auth_headers(user)
      }.not_to have_enqueued_job(ManifestApplyJob)

      expect(response).to have_http_status(:precondition_required)
      body = response.parsed_body
      expect(body["code"]).to eq("removals_required")
      expect(body["removals"].map { |removal| removal["service_name"] }).to eq([ "old-worker" ])
      expect(body["removal_token"]).to be_present
    end

    it "applies the manifest once the exact removals are confirmed" do
      post "/api/projects/#{project.id}/manifest/apply", headers: auth_headers(user)
      token = response.parsed_body.fetch("removal_token")

      expect {
        post "/api/projects/#{project.id}/manifest/apply",
          params: { confirm_removals: true, removal_confirmation_token: token },
          headers: auth_headers(user), as: :json
      }.to have_enqueued_job(ManifestApplyJob).with(project.id, manifest, hash_including(allow_removals: true))

      expect(response).to have_http_status(:ok)
    end

    it "rejects a confirmation issued for a different manifest revision" do
      post "/api/projects/#{project.id}/manifest/apply", headers: auth_headers(user)
      token = response.parsed_body.fetch("removal_token")

      project.update!(manifest_content: "#{manifest}
# edited after review
")

      expect {
        post "/api/projects/#{project.id}/manifest/apply",
          params: { confirm_removals: true, removal_confirmation_token: token },
          headers: auth_headers(user), as: :json
      }.not_to have_enqueued_job(ManifestApplyJob)

      expect(response).to have_http_status(:precondition_required)
      expect(response.parsed_body["error"]).to match(/manifest changed/)
    end

    it "reports the removals in the preview" do
      post "/api/projects/#{project.id}/manifest/preview", headers: auth_headers(user)

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["requires_removal_confirmation"]).to be(true)
      expect(body["removals"].map { |removal| removal["service_name"] }).to eq([ "old-worker" ])
    end
  end

  describe "GET /api/projects/:project_id/manifest/drift" do
    let(:manifest) do
      <<~TOML
        [[services]]
        name = "web"
        category = "app"
        subtype = "web"
        port = 3000

        [[services]]
        name = "db"
        category = "database"
        subtype = "postgres"
      TOML
    end

    before do
      project.update!(manifest_content: manifest, manifest_format: "raildock.toml")
      create(:service, project: project, name: "web", managed_by: :manifest, port: 8080)
      create(:service, project: project, name: "worker", managed_by: :manifest)
      create(:service, project: project, name: "cache", managed_by: :ui)
    end

    it "reports per-service drift and which services can be merged" do
      get "/api/projects/#{project.id}/manifest/drift", headers: auth_headers(user), as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body

      expect(body["supported"]).to be(true)
      expect(body["format"]).to eq("raildock.toml")
      expect(body["drift_detected"]).to be(true)
      expect(body["services"].map { |service| service["name"] }).to contain_exactly("web", "db", "worker")

      web = body["services"].find { |service| service["name"] == "web" }
      expect(web["status"]).to eq("drifted")
      expect(web["changes"].map { |change| change["field"] }).to include("port")
    end
  end

  describe "POST /api/projects/:project_id/manifest/merge" do
    let(:manifest) do
      <<~TOML
        [[services]]
        name = "web"
        category = "app"
        subtype = "web"
        port = 3000
      TOML
    end

    before do
      project.update!(manifest_content: manifest, manifest_format: "raildock.toml")
      create(:service, project: project, name: "web", managed_by: :manifest, port: 8080)
      create(:service, project: project, name: "worker", managed_by: :manifest)
    end

    it "returns the merged manifest for review without saving it" do
      post "/api/projects/#{project.id}/manifest/merge",
        params: { services: [ "web", "worker" ] }, headers: auth_headers(user), as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["adopted"]).to contain_exactly("web", "worker")
      expect(body["skipped"]).to be_empty

      reparsed = ManifestParser.parse(body["content"], filename: "raildock.toml")
      web = reparsed.services.find { |service| service[:name] == "web" }
      expect(web[:port]).to eq(8080)
      expect(reparsed.services.map { |service| service[:name] }).to include("worker")

      expect(project.reload.manifest_content).to eq(manifest)
    end

    it "merges every mergeable service when accept_all is set" do
      post "/api/projects/#{project.id}/manifest/merge",
        params: { accept_all: true }, headers: auth_headers(user), as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["adopted"]).to contain_exactly("web", "worker")
    end

    it "refuses to merge compatibility formats" do
      project.update!(manifest_content: "[build]\nbuilder = \"NIXPACKS\"\n", manifest_format: "railway.toml")

      post "/api/projects/#{project.id}/manifest/merge", headers: auth_headers(user), as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to match(/only supported/)
    end
  end
end
