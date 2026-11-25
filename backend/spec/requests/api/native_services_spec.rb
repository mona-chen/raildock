require "rails_helper"

RSpec.describe "Native Dokku service controls", type: :request do
  let(:user) { create(:user, :admin) }
  let(:service) { create(:service, project: create(:project, server: create(:server))) }
  let(:engine) { instance_double(DokkuEngine) }
  let(:features) { { "cron" => true, "registry" => true, "logs" => true } }
  let(:path) { "/api/services/#{service.id}/native" }
  let(:headers) { auth_headers(user) }

  before do
    allow(DokkuEngine).to receive(:new).and_return(engine)
    allow(DokkuCapabilities).to receive(:new).with(engine).and_return(double(read: { features: features, namespaces: features.keys }))
    allow(engine).to receive(:escape) { |value| Shellwords.escape(value.to_s) }
  end

  it "requires authentication" do
    get path
    expect(response).to have_http_status(:unauthorized)
  end

  it "rejects operations the host does not offer" do
    features["registry"] = false
    expect(engine).not_to receive(:run_with_stdin)
    post path, params: { operation: "registry_login", registry: "ghcr.io", username: "user", password: "secret" }, headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "passes per-app registry credentials through stdin, not command arguments" do
    expect(engine).to receive(:run_with_stdin).with("registry:login #{service.dokku_app_name} --password-stdin ghcr.io user", "secret\n").and_return(success: true)
    post path, params: { operation: "registry_login", registry: "ghcr.io", username: "user", password: "secret" }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("secret")
  end

  it "refuses a task id from another app before calling cron:run" do
    allow(engine).to receive(:cron_list).with(service.dokku_app_name).and_return(success: true, output: '[{"id":"owned"}]')
    expect(engine).not_to receive(:cron_run)
    post path, params: { operation: "cron_run", task_id: "foreign" }, headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "does not pretend a rejected native property succeeded" do
    expect(engine).to receive(:run).with("logs:set #{service.dokku_app_name} max-size 20m").and_return(success: false, output: "rejected")
    post path, params: { operation: "logs_rotation", size_mb: 20 }, headers: headers
    expect(response).to have_http_status(:bad_gateway)
  end
end
