require "rails_helper"

RSpec.describe "Api::ServicesController", type: :request do
  let(:user) { create(:user) }
  let(:server) { create(:server) }
  let(:project) { create(:project, server: server) }
  let!(:service) { create(:service, project: project) }

  describe "GET /api/projects/:project_id/services" do
    context "when unauthenticated" do
      it "returns 401" do
        get "/api/projects/#{project.id}/services"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "when authenticated" do
      it "returns services for the project" do
        get "/api/projects/#{project.id}/services", headers: auth_headers(user)

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json.length).to eq(1)
        expect(json.first["id"]).to eq(service.id)
      end
    end
  end

  describe "GET /api/services/:id" do
    context "when unauthenticated" do
      it "returns 401" do
        get "/api/services/#{service.id}"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "when authenticated" do
      it "returns the service" do
        get "/api/services/#{service.id}", headers: auth_headers(user)

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["id"]).to eq(service.id)
        expect(json["name"]).to eq(service.name)
      end

      it "returns 404 for non-existent service" do
        get "/api/services/999999", headers: auth_headers(user)

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "POST /api/projects/:project_id/services" do
    let(:valid_params) do
      {
        service: {
          name: "api-worker",
          service_type: "app",
          subtype: "web",
          status: "stopped",
          builder: "nixpacks"
        }
      }
    end

    context "when unauthenticated" do
      it "returns 401" do
        post "/api/projects/#{project.id}/services", params: valid_params
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "when authenticated" do
      context "with server ssh_key present" do
        it "creates the service and calls DokkuEngine" do
          allow_any_instance_of(DokkuEngine).to receive(:app_create).and_return({ success: true })
          allow_any_instance_of(DokkuEngine).to receive(:proxy_set).and_return({ success: true })
          allow_any_instance_of(DokkuEngine).to receive(:domain_add).and_return({ success: true })
          allow_any_instance_of(DokkuEngine).to receive(:sync_port_mappings).and_return({ success: true })

          expect {
            post "/api/projects/#{project.id}/services", params: valid_params, headers: auth_headers(user)
          }.to change(Service, :count).by(1)
            .and change(ActivityEvent, :count).by(1)

          expect(response).to have_http_status(:created)
          json = JSON.parse(response.body)
          expect(json["name"]).to eq("api-worker")
          expect(json["config"]["proxy"]["proxyType"]).to eq("traefik")
        end
      end

      context "with server ssh_key blank" do
        let(:server_without_key) { create(:server, ssh_key: nil) }
        let(:project_no_key) { create(:project, server: server_without_key) }

        it "creates the service without calling DokkuEngine" do
          expect_any_instance_of(DokkuEngine).not_to receive(:app_create)

          expect {
            post "/api/projects/#{project_no_key.id}/services", params: valid_params, headers: auth_headers(user)
          }.to change(Service, :count).by(1)

          expect(response).to have_http_status(:created)
        end
      end

      it "returns 422 with invalid data" do
        post "/api/projects/#{project.id}/services", params: { service: { name: "" } }, headers: auth_headers(user)

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "PATCH /api/services/:id" do
    context "when unauthenticated" do
      it "returns 401" do
        patch "/api/services/#{service.id}", params: { service: { name: "updated" } }
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "when authenticated" do
      it "updates the service" do
        patch "/api/services/#{service.id}", params: { service: { name: "updated-name" } }, headers: auth_headers(user)

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["name"]).to eq("updated-name")
      end

      it "returns 404 for non-existent service" do
        patch "/api/services/999999", params: { service: { name: "updated" } }, headers: auth_headers(user)

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "DELETE /api/services/:id" do
    context "when unauthenticated" do
      it "returns 401" do
        delete "/api/services/#{service.id}"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "when authenticated" do
      context "with server ssh_key present" do
        it "requires typed confirmation and destroys nothing without it" do
          expect {
            delete "/api/services/#{service.id}", headers: auth_headers(user)
          }.not_to change(Service, :count)

          expect(response).to have_http_status(:precondition_required)
          expect(response.parsed_body["code"]).to eq("confirmation_required")
        end

        it "destroys the service and calls DokkuEngine when the name is confirmed" do
          allow_any_instance_of(DokkuEngine).to receive(:app_destroy).and_return({ success: true })

          expect {
            delete "/api/services/#{service.id}", params: { confirm: service.name }, headers: auth_headers(user)
          }.to change(Service, :count).by(-1)
            .and change(ActivityEvent, :count).by(1)

          expect(response).to have_http_status(:no_content)
        end

        it "refuses to destroy a datastore when no snapshot can be taken" do
          database = create(:service, :database, project: project)
          allow_any_instance_of(DokkuEngine).to receive(:datastore_destroy).and_return({ success: true })

          expect {
            delete "/api/services/#{database.id}", params: { confirm: database.name }, headers: auth_headers(user)
          }.not_to change(Service, :count)

          expect(response).to have_http_status(:precondition_required)
          expect(response.parsed_body["code"]).to eq("snapshot_required")
          expect(Service.exists?(database.id)).to be true
        end

        it "destroys a datastore after snapshots land on a verified destination" do
          database = create(:service, :database, project: project)
          backup = instance_double(Backup, id: 1)
          snapshot = DestructionSnapshot::Result.new(success: true, backup: backup, destinations: [])
          allow(DestructionSnapshot).to receive(:new).with(database).and_return(instance_double(DestructionSnapshot, call: snapshot))
          allow_any_instance_of(DokkuEngine).to receive(:datastore_destroy).and_return({ success: true })

          expect {
            delete "/api/services/#{database.id}", params: { confirm: database.name }, headers: auth_headers(user)
          }.to change(Service, :count).by(-1)

          expect(response).to have_http_status(:no_content)
        end
      end

      context "with server ssh_key blank" do
        let(:server_without_key) { create(:server, ssh_key: nil) }
        let(:project_no_key) { create(:project, server: server_without_key) }
        let!(:service_no_key) { create(:service, :database, project: project_no_key) }

        it "still refuses to destroy an unsnapshotted datastore" do
          expect_any_instance_of(DokkuEngine).not_to receive(:app_destroy)

          expect {
            delete "/api/services/#{service_no_key.id}", params: { confirm: service_no_key.name }, headers: auth_headers(user)
          }.not_to change(Service, :count)

          expect(response).to have_http_status(:precondition_required)
        end

        it "destroys the service without calling DokkuEngine when data loss is acknowledged" do
          expect_any_instance_of(DokkuEngine).not_to receive(:app_destroy)

          expect {
            delete "/api/services/#{service_no_key.id}",
              params: { confirm: service_no_key.name, force_destroy_data: true },
              headers: auth_headers(user)
          }.to change(Service, :count).by(-1)

          expect(response).to have_http_status(:no_content)
        end
      end

      it "returns 404 for non-existent service" do
        delete "/api/services/999999", headers: auth_headers(user)

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "POST /api/services/:id/deploy" do
    context "when unauthenticated" do
      it "returns 401" do
        post "/api/services/#{service.id}/deploy"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "when authenticated" do
      it "creates a deployment and enqueues a job" do
        expect {
          post "/api/services/#{service.id}/deploy", params: { branch: "feature-x", commit_sha: "abc1234" }, headers: auth_headers(user)
        }.to change(Deployment, :count).by(1)
          .and change(ActivityEvent, :count).by(1)

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["status"]).to eq("pending")
        expect(json["branch"]).to eq("feature-x")
        expect(json["commit_sha"]).to eq("abc1234")

        service.reload
        expect(service.status).to eq("deploying")
      end

      it "defaults branch to service branch or main" do
        post "/api/services/#{service.id}/deploy", headers: auth_headers(user)

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["branch"]).to be_present
      end

      it "returns 404 for non-existent service" do
        post "/api/services/999999/deploy", headers: auth_headers(user)

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "POST /api/services/:id/rollback" do
    let!(:target_deployment) { create(:deployment, service: service, commit_sha: "oldsha1", branch: "main") }

    context "when unauthenticated" do
      it "returns 401" do
        post "/api/services/#{service.id}/rollback", params: { deployment_id: target_deployment.id }
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "when authenticated" do
      it "creates a rollback deployment" do
        expect {
          post "/api/services/#{service.id}/rollback", params: { deployment_id: target_deployment.id }, headers: auth_headers(user)
        }.to change(Deployment, :count).by(1)
          .and change(ActivityEvent, :count).by(1)

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["status"]).to eq("pending")
        expect(json["commit_sha"]).to eq("oldsha1")
      end

      it "returns 404 for non-existent deployment" do
        post "/api/services/#{service.id}/rollback", params: { deployment_id: 999999 }, headers: auth_headers(user)

        expect(response).to have_http_status(:not_found)
      end

      it "rejects a git rollback without a precise commit SHA" do
        service.update!(git_repo: "https://github.com/acme/app.git")
        target_deployment.update!(commit_sha: nil)

        expect {
          post "/api/services/#{service.id}/rollback",
            params: { deployment_id: target_deployment.id },
            headers: auth_headers(user)
        }.not_to change(Deployment, :count)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(JSON.parse(response.body)["error"]).to match(/no commit SHA/)
      end
    end
  end

  describe "POST /api/services/:id/scale" do
    let!(:process_type) { create(:process_type, service: service, name: "web", quantity: 1) }

    context "when unauthenticated" do
      it "returns 401" do
        post "/api/services/#{service.id}/scale", params: { process_name: "web", quantity: 3 }
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "when authenticated" do
      context "with server ssh_key present" do
        it "scales the process and calls DokkuEngine" do
          allow_any_instance_of(DokkuEngine).to receive(:ps_scale).and_return({ success: true })

          post "/api/services/#{service.id}/scale", params: { process_name: "web", quantity: 3 }, headers: auth_headers(user)

          expect(response).to have_http_status(:ok)
          process_type.reload
          expect(process_type.quantity).to eq(3)
        end
      end

      context "with server ssh_key blank" do
        let(:server_without_key) { create(:server, ssh_key: nil) }
        let(:project_no_key) { create(:project, server: server_without_key) }
        let!(:service_no_key) { create(:service, project: project_no_key) }
        let!(:process_no_key) { create(:process_type, service: service_no_key, name: "web", quantity: 1) }

        it "scales without calling DokkuEngine" do
          expect_any_instance_of(DokkuEngine).not_to receive(:ps_scale)

          post "/api/services/#{service_no_key.id}/scale", params: { process_name: "web", quantity: 2 }, headers: auth_headers(user)

          expect(response).to have_http_status(:ok)
          process_no_key.reload
          expect(process_no_key.quantity).to eq(2)
        end
      end

      it "returns 404 for non-existent process type" do
        post "/api/services/#{service.id}/scale", params: { process_name: "worker", quantity: 2 }, headers: auth_headers(user)

        expect(response).to have_http_status(:not_found)
      end

      # Scaling a one-shot deploy task would run it in a restart loop.
      it "refuses to scale a one-shot deploy task" do
        create(:process_type, service: service, name: "release", quantity: 0)
        expect_any_instance_of(DokkuEngine).not_to receive(:ps_scale)

        post "/api/services/#{service.id}/scale", params: { process_name: "release", quantity: 1 }, headers: auth_headers(user)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(service.process_types.find_by(name: "release").quantity).to eq(0)
      end
    end
  end

  describe "GET /api/services/:id/logs" do
    context "when unauthenticated" do
      it "returns 401" do
        get "/api/services/#{service.id}/logs"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "when authenticated" do
      context "with server ssh_key present" do
        it "returns real logs from DokkuEngine" do
          allow_any_instance_of(DokkuEngine).to receive(:logs).and_return(
            { success: true, output: "line1\nline2" }
          )

          get "/api/services/#{service.id}/logs", headers: auth_headers(user)

          expect(response).to have_http_status(:ok)
          json = JSON.parse(response.body)
          expect(json.length).to eq(2)
          expect(json.first["message"]).to eq("line1")
        end
      end

      context "with server ssh_key blank" do
        let(:server_without_key) { create(:server, ssh_key: nil) }
        let(:project_no_key) { create(:project, server: server_without_key) }
        let!(:service_no_key) { create(:service, project: project_no_key) }

        it "falls back to stored logs" do
          get "/api/services/#{service_no_key.id}/logs", headers: auth_headers(user)

          expect(response).to have_http_status(:ok)
          expect(JSON.parse(response.body)).to be_an(Array)
        end
      end

      it "returns 404 for non-existent service" do
        get "/api/services/999999/logs", headers: auth_headers(user)

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "GET /api/services/:id/metrics" do
    context "when unauthenticated" do
      it "returns 401" do
        get "/api/services/#{service.id}/metrics"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "when authenticated" do
      context "with server ssh_key present" do
        it "returns real docker stats metrics" do
          allow_any_instance_of(HostEngine).to receive(:dokku_container_name).and_return("app.web.1")
          allow_any_instance_of(HostEngine).to receive(:docker_stats).and_return(
            cpu: 35.5, memory: 50.0, memory_used: 1073741824, memory_limit: 2147483648
          )

          get "/api/services/#{service.id}/metrics", headers: auth_headers(user)

          expect(response).to have_http_status(:ok)
          json = JSON.parse(response.body)
          expect(json["cpu"]).to eq(35.5)
          expect(json["memory"]).to eq(50.0)
          expect(json["memoryLimit"]).to eq(2147483648)
        end
      end

      context "with server ssh_key blank" do
        let(:server_without_key) { create(:server, ssh_key: nil) }
        let(:project_no_key) { create(:project, server: server_without_key) }
        let!(:service_no_key) { create(:service, project: project_no_key) }

        it "returns fallback placeholder metrics" do
          get "/api/services/#{service_no_key.id}/metrics", headers: auth_headers(user)

          expect(response).to have_http_status(:ok)
          json = JSON.parse(response.body)
          expect(json).to have_key("cpu")
          expect(json).to have_key("memory")
        end
      end

      it "returns 404 for non-existent service" do
        get "/api/services/999999/metrics", headers: auth_headers(user)

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "GET /api/services/:id/metrics_history" do
    it "returns ordered time series samples" do
      create(:service_metric, service: service, cpu: 10, memory: 20, sampled_at: 10.minutes.ago)
      create(:service_metric, service: service, cpu: 15, memory: 25, sampled_at: 5.minutes.ago)

      get "/api/services/#{service.id}/metrics_history?hours=24", headers: auth_headers(user)

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["service"]).to eq(service.name)
      expect(json["window_hours"]).to eq(24)
      expect(json["samples"].length).to eq(2)
      expect(json["samples"].map { |s| s["cpu"] }).to eq([ 10, 15 ])
      expect(json["samples"].first["at"]).to be_present
    end

    it "defaults to a 24h window" do
      get "/api/services/#{service.id}/metrics_history", headers: auth_headers(user)

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["window_hours"]).to eq(24)
    end

    it "excludes samples outside the window" do
      create(:service_metric, service: service, sampled_at: 3.days.ago)

      get "/api/services/#{service.id}/metrics_history?hours=24", headers: auth_headers(user)

      expect(JSON.parse(response.body)["samples"]).to be_empty
    end
  end

  describe "GET /api/services/:id/container_status" do
    context "when unauthenticated" do
      it "returns 401" do
        get "/api/services/#{service.id}/container_status"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "when authenticated" do
      context "with server ssh_key present" do
        it "returns running status from DokkuEngine" do
          allow_any_instance_of(DokkuEngine).to receive(:container_status).and_return(
            { success: true, output: "true" }
          )

          get "/api/services/#{service.id}/container_status", headers: auth_headers(user)

          expect(response).to have_http_status(:ok)
          json = JSON.parse(response.body)
          expect(json["status"]).to eq("running")
          expect(json["output"]).to eq("true")
        end

        it "falls back to service status on failed engine call" do
          allow_any_instance_of(DokkuEngine).to receive(:container_status).and_return(
            { success: false, output: "error" }
          )

          get "/api/services/#{service.id}/container_status", headers: auth_headers(user)

          expect(response).to have_http_status(:ok)
          json = JSON.parse(response.body)
          expect(json["status"]).to eq(service.status)
        end
      end

      context "with server ssh_key blank" do
        let(:server_without_key) { create(:server, ssh_key: nil) }
        let(:project_no_key) { create(:project, server: server_without_key) }
        let!(:service_no_key) { create(:service, project: project_no_key, status: "stopped") }

        it "returns service status without calling DokkuEngine" do
          expect_any_instance_of(DokkuEngine).not_to receive(:container_status)

          get "/api/services/#{service_no_key.id}/container_status", headers: auth_headers(user)

          expect(response).to have_http_status(:ok)
          json = JSON.parse(response.body)
          expect(json["status"]).to eq("stopped")
        end
      end

      it "returns 404 for non-existent service" do
        get "/api/services/999999/container_status", headers: auth_headers(user)

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "POST /api/services/:id/link" do
    let(:target_service) { create(:service, :database, project: project, subtype: "postgres") }

    context "when unauthenticated" do
      it "returns 401" do
        post "/api/services/#{service.id}/link", params: { target_id: target_service.id }
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "when authenticated" do
      context "with server ssh_key present and target is database" do
        it "creates a link and calls DokkuEngine" do
          allow_any_instance_of(DokkuEngine).to receive(:postgres_link).and_return({ success: true })
          allow_any_instance_of(DokkuEngine).to receive(:run).and_return({ success: true, output: "" })
          allow_any_instance_of(ProjectNetworkManager).to receive(:connect_service)
          allow_any_instance_of(ProjectNetworkManager).to receive(:ensure_linked_aliases)
          allow_any_instance_of(ProjectNetworkManager).to receive(:inject_internal_hostnames)

          expect {
            post "/api/services/#{service.id}/link", params: { target_id: target_service.id }, headers: auth_headers(user)
          }.to change(ServiceLink, :count).by(1)
            .and change(ActivityEvent, :count).by(1)

          expect(response).to have_http_status(:ok)
          json = JSON.parse(response.body)
          expect(json["success"]).to be true
          expect(json["linked_service_ids"]).to include(target_service.id)
        end
      end

      context "with server ssh_key blank" do
        let(:server_without_key) { create(:server, ssh_key: nil) }
        let(:project_no_key) { create(:project, server: server_without_key) }
        let(:app_service) { create(:service, project: project_no_key) }
        let(:db_service) { create(:service, :database, project: project_no_key, subtype: "postgres") }

        it "creates a link without calling DokkuEngine" do
          expect_any_instance_of(DokkuEngine).not_to receive(:postgres_link)

          post "/api/services/#{app_service.id}/link", params: { target_id: db_service.id }, headers: auth_headers(user)

          expect(response).to have_http_status(:ok)
        end
      end

      it "returns 404 for non-existent target service" do
        post "/api/services/#{service.id}/link", params: { target_id: 999999 }, headers: auth_headers(user)

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "POST /api/services/:id/unlink" do
    let(:target_service) { create(:service, :database, project: project, subtype: "postgres") }
    let!(:service_link) { create(:service_link, from_service: service, to_service: target_service) }

    context "when unauthenticated" do
      it "returns 401" do
        post "/api/services/#{service.id}/unlink", params: { target_id: target_service.id }
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "when authenticated" do
      context "with server ssh_key present and target is database" do
        it "destroys the link and calls DokkuEngine" do
          allow_any_instance_of(DokkuEngine).to receive(:postgres_unlink).and_return({ success: true })
          allow_any_instance_of(DokkuEngine).to receive(:run).and_return({ success: true, output: "" })

          expect {
            post "/api/services/#{service.id}/unlink", params: { target_id: target_service.id }, headers: auth_headers(user)
          }.to change(ServiceLink, :count).by(-1)
            .and change(ActivityEvent, :count).by(1)

          expect(response).to have_http_status(:ok)
          json = JSON.parse(response.body)
          expect(json["success"]).to be true
          expect(json["linked_service_ids"]).not_to include(target_service.id)
        end
      end

      context "with server ssh_key blank" do
        let(:server_without_key) { create(:server, ssh_key: nil) }
        let(:project_no_key) { create(:project, server: server_without_key) }
        let(:app_service) { create(:service, project: project_no_key) }
        let(:db_service) { create(:service, :database, project: project_no_key, subtype: "postgres") }
        let!(:link_no_key) { create(:service_link, from_service: app_service, to_service: db_service) }

        it "destroys the link without calling DokkuEngine" do
          expect_any_instance_of(DokkuEngine).not_to receive(:postgres_unlink)

          post "/api/services/#{app_service.id}/unlink", params: { target_id: db_service.id }, headers: auth_headers(user)

          expect(response).to have_http_status(:ok)
        end
      end

      it "returns 404 for non-existent link" do
        other_target = create(:service, project: project)
        post "/api/services/#{service.id}/unlink", params: { target_id: other_target.id }, headers: auth_headers(user)

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "POST /api/services/:id/backup" do
    let(:database_service) { create(:service, :database, project: project, subtype: "postgres") }

    context "when unauthenticated" do
      it "returns 401" do
        post "/api/services/#{service.id}/backup"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "when authenticated" do
      context "with server ssh_key present" do
        it "queues a durable backup" do
          expect {
            post "/api/services/#{database_service.id}/backup", headers: auth_headers(user)
          }.to change(Backup, :count).by(1)
            .and have_enqueued_job(BackupJob)

          expect(response).to have_http_status(:accepted)
          json = JSON.parse(response.body)
          expect(json["success"]).to be true
          expect(json["backup"]["status"]).to eq("pending")
        end

        it "rejects backups for application services" do
          post "/api/services/#{service.id}/backup", headers: auth_headers(user)

          expect(response).to have_http_status(:unprocessable_entity)
          expect(JSON.parse(response.body)["error"]).to match(/only available for databases/)
        end
      end

      context "with server ssh_key blank" do
        let(:server_without_key) { create(:server, ssh_key: nil) }
        let(:project_no_key) { create(:project, server: server_without_key) }
        let!(:service_no_key) { create(:service, :database, project: project_no_key) }

        it "returns 422 without calling DokkuEngine" do
          expect_any_instance_of(DokkuEngine).not_to receive(:run)

          post "/api/services/#{service_no_key.id}/backup", headers: auth_headers(user)

          expect(response).to have_http_status(:unprocessable_entity)
          json = JSON.parse(response.body)
          expect(json["error"]).to eq("No server configured")
        end
      end

      it "returns 404 for non-existent service" do
        post "/api/services/999999/backup", headers: auth_headers(user)

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "POST /api/services/:id/restore" do
    let(:database_service) { create(:service, :database, project: project, subtype: "postgres") }

    context "when unauthenticated" do
      it "returns 401" do
        post "/api/services/#{service.id}/restore"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "when authenticated" do
      context "with server ssh_key present" do
        it "returns success and creates an activity event" do
          allow_any_instance_of(DokkuEngine).to receive(:datastore_import_from).and_return({ success: true, output: "ok" })
          allow_any_instance_of(DestructionSnapshot).to receive(:call).and_return(
            DestructionSnapshot::Result.new(success: true, backup: nil, destinations: [], error: nil)
          )

          expect {
            post "/api/services/#{database_service.id}/restore?confirm=#{database_service.name}", headers: auth_headers(user)
          }.to change(ActivityEvent, :count).by(1)

          expect(response).to have_http_status(:ok)
          json = JSON.parse(response.body)
          expect(json["success"]).to be true
          expect(json["message"]).to eq("Restore completed")
        end

        it "requires the service name before overwriting live data" do
          expect_any_instance_of(DokkuEngine).not_to receive(:datastore_import_from)

          post "/api/services/#{database_service.id}/restore", headers: auth_headers(user)

          expect(response).to have_http_status(:precondition_required)
          expect(response.parsed_body["code"]).to eq("confirmation_required")
        end

        it "refuses to overwrite live data when no safety snapshot can be taken" do
          failure = DestructionSnapshot::Result.new(
            success: false, backup: nil, destinations: [], error: "no verified backup destination is configured"
          )
          allow(DestructionSnapshot).to receive(:new).and_return(instance_double(DestructionSnapshot, call: failure))
          expect_any_instance_of(DokkuEngine).not_to receive(:datastore_import_from)

          post "/api/services/#{database_service.id}/restore?confirm=#{database_service.name}", headers: auth_headers(user)

          expect(response).to have_http_status(:precondition_required)
          expect(response.parsed_body["code"]).to eq("snapshot_required")
          expect(response.parsed_body["restore"]["data_bearing"]).to be(true)
        end

        it "restores when the unrecoverable overwrite is explicitly acknowledged" do
          failure = DestructionSnapshot::Result.new(
            success: false, backup: nil, destinations: [], error: "no verified backup destination is configured"
          )
          allow(DestructionSnapshot).to receive(:new).and_return(instance_double(DestructionSnapshot, call: failure))
          allow_any_instance_of(DokkuEngine).to receive(:datastore_import_from).and_return({ success: true, output: "ok" })

          post "/api/services/#{database_service.id}/restore?confirm=#{database_service.name}&force_destroy_data=true",
            headers: auth_headers(user)

          expect(response).to have_http_status(:ok)
          expect(ActivityEvent.where(action: :warning).last.message).to include("without a pre-restore snapshot")
        end
      end

      context "with server ssh_key blank" do
        let(:server_without_key) { create(:server, ssh_key: nil) }
        let(:project_no_key) { create(:project, server: server_without_key) }
        let!(:service_no_key) { create(:service, :database, project: project_no_key) }

        it "returns 422 without calling DokkuEngine" do
          expect_any_instance_of(DokkuEngine).not_to receive(:run)

          # Acknowledge the unrecoverable overwrite so the request reaches the
          # "no server configured" branch this example is about.
          post "/api/services/#{service_no_key.id}/restore?confirm=#{service_no_key.name}&force_destroy_data=true",
            headers: auth_headers(user)

          expect(response).to have_http_status(:unprocessable_entity)
          json = JSON.parse(response.body)
          expect(json["error"]).to eq("No server configured")
        end
      end

      it "returns 404 for non-existent service" do
        post "/api/services/999999/restore", headers: auth_headers(user)

        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
