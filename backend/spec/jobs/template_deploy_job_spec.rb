require "rails_helper"

RSpec.describe TemplateDeployJob, type: :job do
  let(:project) { create(:project, server: create(:server)) }

  it "fails only the pending deployments belonging to its invocation when setup cannot start" do
    target_service = create(:service, project: project, status: :deploying)
    unrelated_service = create(:service, project: project, status: :deploying)
    target_deployment = create(:deployment, service: target_service, status: :pending)
    unrelated_deployment = create(:deployment, service: unrelated_service, status: :pending)

    described_class.perform_now(
      project.id,
      "missing-template",
      [ target_service.id ],
      { target_service.id => target_deployment.id }
    )

    expect(target_deployment.reload).to have_attributes(
      status: "failed",
      completed_at: be_present
    )
    expect(target_service.reload.status).to eq("error")
    expect(unrelated_deployment.reload.status).to eq("pending")
    expect(unrelated_service.reload.status).to eq("deploying")
  end
end
