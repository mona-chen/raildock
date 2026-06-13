require "rails_helper"

RSpec.describe "Api::TemplatesController", type: :request do
  let(:user) { create(:user) }
  let(:project) { create(:project, user: user, server: nil) }

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
        expect(json.length).to be >= 100

        ids = json.map { |t| t["id"] }
        expect(ids).to include("pocketbase", "linkding")
      end

      it "includes services for each template" do
        get "/api/templates", headers: auth_headers(user)

        json = JSON.parse(response.body)
        pocketbase = json.find { |t| t["id"] == "pocketbase" }
        expect(pocketbase["services"].length).to eq(1)
        expect(pocketbase["services"].map { |s| s["name"] }).to contain_exactly("pocketbase")
      end
    end
  end

  describe "POST /api/templates/:id/deploy" do
    context "when unauthenticated" do
      it "returns 401" do
        post "/api/templates/pocketbase/deploy", params: { project_id: project.id }
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "when authenticated" do
      it "deploys a single-service template to the project" do
        expect {
          post "/api/templates/pocketbase/deploy", params: { project_id: project.id }, headers: auth_headers(user)
        }.to change(Service, :count).by(1)
          .and change(ProcessType, :count).by(1)

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["created"].length).to eq(1)

        names = json["created"].map { |s| s["name"] }
        expect(names).to contain_exactly("pocketbase")
      end

      it "deploys another current catalog template to the project" do
        expect {
          post "/api/templates/linkding/deploy", params: { project_id: project.id }, headers: auth_headers(user)
        }.to change(Service, :count).by(1)
          .and change(ProcessType, :count).by(1)

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["created"].length).to eq(1)
      end

      it "configures Alexandrie RustFS to match Dokku storage ownership" do
        post "/api/templates/alexandrie/deploy",
          params: { project_id: project.id },
          headers: auth_headers(user)

        expect(response).to have_http_status(:ok)
        rustfs = project.services.find_by!(name: "rustfs")
        expect(rustfs.config.fetch("dockerOptions")).to include(
          "phase" => "deploy",
          "option" => "--user=1000:1000"
        )
      end

      it "returns 404 for unknown template" do
        post "/api/templates/unknown/deploy", params: { project_id: project.id }, headers: auth_headers(user)

        expect(response).to have_http_status(:not_found)
        expect(JSON.parse(response.body)["error"]).to eq("Template not found")
      end

      it "returns 404 for unknown project" do
        post "/api/templates/pocketbase/deploy", params: { project_id: 999999 }, headers: auth_headers(user)

        expect(response).to have_http_status(:not_found)
        expect(JSON.parse(response.body)["error"]).to eq("Project not found")
      end

      it "creates pending deployments and passes exact invocation records to the job" do
        project.update!(server: create(:server))
        allow(TemplateDeployJob).to receive(:perform_later)

        post "/api/templates/pocketbase/deploy",
          params: { project_id: project.id },
          headers: auth_headers(user)

        created_service = project.services.find_by!(name: "pocketbase")
        deployment = created_service.deployments.find_by!(status: :pending)

        expect(created_service.status).to eq("deploying")
        expect(TemplateDeployJob).to have_received(:perform_later).with(
          project.id,
          "pocketbase",
          [ created_service.id ],
          { created_service.id.to_s => deployment.id }
        )
      end
    end
  end
end
