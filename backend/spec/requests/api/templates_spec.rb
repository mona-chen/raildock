require "rails_helper"

RSpec.describe "Api::TemplatesController", type: :request do
  let(:user) { create(:user) }
  let(:project) { create(:project) }

  describe "GET /api/templates" do
    context "when unauthenticated" do
      it "returns 401" do
        get "/api/templates"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "when authenticated" do
      it "returns the list of templates" do
        get "/api/templates", headers: auth_headers(user)

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json).to be_an(Array)
        expect(json.length).to eq(4)

        ids = json.map { |t| t["id"] }
        expect(ids).to contain_exactly("rails-api", "nodejs-app", "python-django", "wordpress")
      end

      it "includes services for each template" do
        get "/api/templates", headers: auth_headers(user)

        json = JSON.parse(response.body)
        rails = json.find { |t| t["id"] == "rails-api" }
        expect(rails["services"].length).to eq(3)
        expect(rails["services"].map { |s| s["name"] }).to contain_exactly("web", "database", "cache")
      end
    end
  end

  describe "POST /api/templates/:id/deploy" do
    context "when unauthenticated" do
      it "returns 401" do
        post "/api/templates/rails-api/deploy", params: { project_id: project.id }
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "when authenticated" do
      it "deploys the rails-api template to the project" do
        expect {
          post "/api/templates/rails-api/deploy", params: { project_id: project.id }, headers: auth_headers(user)
        }.to change(Service, :count).by(3)
          .and change(ProcessType, :count).by(1)

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["created"].length).to eq(3)

        names = json["created"].map { |s| s["name"] }
        expect(names).to contain_exactly("web", "database", "cache")
      end

      it "deploys the nodejs-app template to the project" do
        expect {
          post "/api/templates/nodejs-app/deploy", params: { project_id: project.id }, headers: auth_headers(user)
        }.to change(Service, :count).by(2)
          .and change(ProcessType, :count).by(1)

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["created"].length).to eq(2)
      end

      it "returns 404 for unknown template" do
        post "/api/templates/unknown/deploy", params: { project_id: project.id }, headers: auth_headers(user)

        expect(response).to have_http_status(:not_found)
        expect(JSON.parse(response.body)["error"]).to eq("Template not found")
      end

      it "returns 404 for unknown project" do
        post "/api/templates/rails-api/deploy", params: { project_id: 999999 }, headers: auth_headers(user)

        expect(response).to have_http_status(:not_found)
        expect(JSON.parse(response.body)["error"]).to eq("Project not found")
      end
    end
  end
end
