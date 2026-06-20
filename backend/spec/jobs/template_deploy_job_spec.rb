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

  it "orders app deployments by service links and excludes datastore links" do
    frontend = create(:service, project: project, name: "frontend")
    backend = create(:service, project: project, name: "backend")
    rustfs = create(:service, project: project, name: "rustfs")
    mysql = create(:service, :database, project: project, name: "mysql")

    create(:service_link, from_service: frontend, to_service: backend)
    create(:service_link, from_service: frontend, to_service: mysql)
    create(:service_link, from_service: backend, to_service: rustfs)
    create(:service_link, from_service: backend, to_service: mysql)
    create(:service_link, from_service: rustfs, to_service: mysql)

    services = [ frontend, backend, rustfs ]
    deployments = services.to_h do |service|
      [ service.id, create(:deployment, service: service, status: :pending) ]
    end
    job = described_class.new

    sorted = job.send(:topo_sort_by_depends_on, services)
    entries = job.send(:deployment_sequence_entries, sorted, deployments)
    entries_by_service = entries.index_by { |entry| entry[:service_id] }

    expect(sorted).to eq([ rustfs, backend, frontend ])
    expect(entries_by_service.fetch(rustfs.id)[:depends_on_deployment_ids]).to be_empty
    expect(entries_by_service.fetch(backend.id)[:depends_on_deployment_ids]).to eq([ deployments.fetch(rustfs.id).id ])
    expect(entries_by_service.fetch(frontend.id)[:depends_on_deployment_ids]).to eq([ deployments.fetch(backend.id).id ])
  end

  it "broadcasts template failures through the authorized project stream" do
    allow(ProjectChannel).to receive(:broadcast_to)

    described_class.new.send(:broadcast_error, project.id, "Template failed")

    expect(ProjectChannel).to have_received(:broadcast_to).with(
      project,
      hash_including(type: "template_deploy", status: "failed", message: "Template failed")
    )
  end
end
