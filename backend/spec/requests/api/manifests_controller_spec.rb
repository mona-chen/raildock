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
          subtype = "node"
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
end
