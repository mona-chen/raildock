require "rails_helper"

RSpec.describe DeploymentSequenceJob, type: :job do
  let(:project) { create(:project) }
  let(:database_api) { create(:service, project: project, name: "api") }
  let(:web) { create(:service, project: project, name: "web") }
  let(:api_deployment) { create(:deployment, service: database_api, status: :pending) }
  let(:web_deployment) { create(:deployment, service: web, status: :pending) }

  it "runs a dependent deployment only after its prerequisite succeeds" do
    execution_order = []
    allow(DeploymentJob).to receive(:perform_now) do |_service_id, deployment_id|
      execution_order << deployment_id
      Deployment.find(deployment_id).update!(status: :succeeded)
    end

    described_class.perform_now([
      { service_id: database_api.id, deployment_id: api_deployment.id, depends_on_deployment_ids: [] },
      { service_id: web.id, deployment_id: web_deployment.id, depends_on_deployment_ids: [ api_deployment.id ] }
    ])

    expect(execution_order).to eq([ api_deployment.id, web_deployment.id ])
  end

  it "cancels a dependent deployment when its prerequisite fails" do
    allow(DeploymentsChannel).to receive(:broadcast_to)
    allow(DeploymentJob).to receive(:perform_now) do |_service_id, deployment_id|
      Deployment.find(deployment_id).update!(status: :failed)
    end

    described_class.perform_now([
      { service_id: database_api.id, deployment_id: api_deployment.id, depends_on_deployment_ids: [] },
      { service_id: web.id, deployment_id: web_deployment.id, depends_on_deployment_ids: [ api_deployment.id ] }
    ])

    expect(web_deployment.reload).to be_cancelled
    expect(web_deployment.deploy_log).to include(api_deployment.id.to_s)
  end

  it "skips a deployment cancelled while it was queued" do
    allow(DeploymentJob).to receive(:perform_now)
    web_deployment.cancel!

    described_class.perform_now([
      { service_id: web.id, deployment_id: web_deployment.id, depends_on_deployment_ids: [] }
    ])

    expect(DeploymentJob).not_to have_received(:perform_now)
  end
end
