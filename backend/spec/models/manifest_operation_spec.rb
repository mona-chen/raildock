require "rails_helper"

RSpec.describe ManifestOperation do
  let(:project) { create(:project) }
  let(:old_service) { create(:service, project: project, managed_by: :manifest, name: "old") }
  let(:replacement) { create(:service, project: project, name: "replacement") }
  let(:deployment) { create(:deployment, service: replacement, status: :pending) }
  let(:operation) do
    project.manifest_operations.create!(deployment_ids: [ deployment.id ], removals: [ { id: old_service.id, dokku_app_name: old_service.dokku_app_name } ])
  end
  let(:engine) { instance_double(DokkuEngine, app_destroy: { success: true }) }
  before { allow(DokkuEngine).to receive(:new).and_return(engine) }

  it "keeps the old service while deployment is pending" do
    operation.finalize_if_ready!
    expect(operation.reload.status).to eq("waiting")
    expect(Service.exists?(old_service.id)).to be(true)
    expect(engine).not_to have_received(:app_destroy)
  end

  it "blocks removals when a deployment fails" do
    operation
    deployment.update!(status: :failed)
    operation.finalize_if_ready!
    expect(operation.reload.status).to eq("failed")
    expect(Service.exists?(old_service.id)).to be(true)
    expect(engine).not_to have_received(:app_destroy)
  end

  it "removes only the confirmed identity after deployment succeeds, once" do
    operation
    other = create(:service, project: project, name: "unrelated", managed_by: :manifest)
    deployment.update!(status: :succeeded)
    2.times { operation.finalize_if_ready! }
    expect(operation.reload.status).to eq("succeeded")
    expect(Service.exists?(old_service.id)).to be(false)
    expect(Service.exists?(other.id)).to be(true)
    expect(engine).to have_received(:app_destroy).once
  end

  it "refuses an identity changed after confirmation" do
    operation
    old_service.update!(dokku_app_name: "changed-identity")
    deployment.update!(status: :succeeded)
    operation.finalize_if_ready!
    expect(operation.reload.status).to eq("failed")
    expect(Service.exists?(old_service.id)).to be(true)
  end

  it "does not interpret a missing deployment as success" do
    operation.update!(deployment_ids: [ 99999999 ])
    operation.finalize_if_ready!
    expect(operation.reload.status).to eq("failed")
    expect(Service.exists?(old_service.id)).to be(true)
  end
end
