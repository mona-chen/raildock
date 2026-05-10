require "rails_helper"

RSpec.describe "Api::ProjectsController", type: :request do
  let(:user) { create(:user) }
  let!(:project) { create(:project) }
  let!(:service) { create(:service, project: project) }

  describe "GET /api/projects" do
    context "when unauthenticated" do
      it "returns 401" do
        get "/api/projects"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "when authenticated" do
      it "returns all projects with service_ids" do
        get "/api/projects", headers: auth_headers(user)

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json.length).to eq(1)
        expect(json.first["id"]).to eq(project.id)
        expect(json.first["service_ids"]).to include(service.id)
      end
    end
  end

  describe "GET /api/projects/:id" do
    context "when unauthenticated" do
      it "returns 401" do
        get "/api/projects/#{project.id}"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "when authenticated" do
      it "returns the project with services" do
        get "/api/projects/#{project.id}", headers: auth_headers(user)

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["id"]).to eq(project.id)
        expect(json["services"]).to be_present
        expect(json["services"].first["id"]).to eq(service.id)
      end

      it "returns 404 for non-existent project" do
        get "/api/projects/999999", headers: auth_headers(user)

        expect(response).to have_http_status(:not_found)
        expect(JSON.parse(response.body)["error"]).to eq("Not found")
      end
    end
  end

  describe "POST /api/projects" do
    let(:server) { create(:server) }
    let(:valid_params) do
      {
        project: {
          name: "New Project",
          description: "A test project",
          environment: "staging",
          server_id: server.id
        }
      }
    end

    context "when unauthenticated" do
      it "returns 401" do
        post "/api/projects", params: valid_params
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "when authenticated" do
      it "creates a project with valid data" do
        expect {
          post "/api/projects", params: valid_params, headers: auth_headers(user)
        }.to change(Project, :count).by(1)
          .and change(ActivityEvent, :count).by(1)

        expect(response).to have_http_status(:created)
        json = JSON.parse(response.body)
        expect(json["name"]).to eq("New Project")
      end

      it "returns 422 with invalid data" do
        post "/api/projects", params: { project: { name: "", environment: "staging" } }, headers: auth_headers(user)

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "DELETE /api/projects/:id" do
    context "when unauthenticated" do
      it "returns 401" do
        delete "/api/projects/#{project.id}"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "when authenticated" do
      it "destroys the project" do
        expect {
          delete "/api/projects/#{project.id}", headers: auth_headers(user)
        }.to change(Project, :count).by(-1)

        expect(response).to have_http_status(:no_content)
      end

      it "returns 404 for non-existent project" do
        delete "/api/projects/999999", headers: auth_headers(user)

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "PATCH /api/projects/:id/shared_vars" do
    context "when unauthenticated" do
      it "returns 401" do
        patch "/api/projects/#{project.id}/shared_vars", params: { vars: ["KEY=value"] }
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "when authenticated" do
      it "updates shared vars" do
        patch "/api/projects/#{project.id}/shared_vars", params: { vars: ["KEY=value", "FOO=bar"] }, headers: auth_headers(user)

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["shared_vars"]).to contain_exactly("KEY=value", "FOO=bar")
      end

      it "clears shared vars when empty array passed" do
        patch "/api/projects/#{project.id}/shared_vars", params: { vars: [] }.to_json, headers: auth_headers(user).merge("Content-Type" => "application/json")

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["shared_vars"]).to eq([])
      end

      it "returns 404 for non-existent project" do
        patch "/api/projects/999999/shared_vars", params: { vars: ["KEY=value"] }, headers: auth_headers(user)

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "GET /api/projects/:id/activity" do
    let!(:event) { create(:activity_event, project: project) }

    context "when unauthenticated" do
      it "returns 401" do
        get "/api/projects/#{project.id}/activity"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "when authenticated" do
      it "returns activity events for the project" do
        get "/api/projects/#{project.id}/activity", headers: auth_headers(user)

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json.length).to eq(1)
        expect(json.first["id"]).to eq(event.id)
      end

      it "returns 404 for non-existent project" do
        get "/api/projects/999999/activity", headers: auth_headers(user)

        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
