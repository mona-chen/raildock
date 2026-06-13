require "rails_helper"

RSpec.describe ReconcileStaleDeploymentsJob, type: :job do
  let(:service) { create(:service, status: :deploying) }
  let(:now) { Time.zone.parse("2026-06-13 12:00:00") }

  before do
    allow(DeploymentsChannel).to receive(:broadcast_to)
  end

  it "fails a deployment that has been pending beyond the queue timeout" do
    deployment = create(
      :deployment,
      service: service,
      status: :pending,
      started_at: now - 31.minutes
    )

    described_class.perform_now(now: now)

    expect(deployment.reload).to have_attributes(status: "failed", completed_at: now)
    expect(deployment.deploy_log).to match(/timed out waiting for a worker/)
    expect(service.reload.status).to eq("error")
  end

  it "leaves recent pending deployments alone" do
    deployment = create(
      :deployment,
      service: service,
      status: :pending,
      started_at: now - 5.minutes
    )

    described_class.perform_now(now: now)

    expect(deployment.reload.status).to eq("pending")
    expect(service.reload.status).to eq("deploying")
  end

  it "keeps the service deploying when another active deployment remains" do
    stale = create(
      :deployment,
      service: service,
      status: :pending,
      started_at: now - 31.minutes
    )
    create(
      :deployment,
      service: service,
      status: :pending,
      started_at: now - 5.minutes
    )

    described_class.perform_now(now: now)

    expect(stale.reload.status).to eq("failed")
    expect(service.reload.status).to eq("deploying")
  end
end
