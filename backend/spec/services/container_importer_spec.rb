require "rails_helper"

RSpec.describe ContainerImporter do
  let(:organization) { create(:organization) }
  let(:owner) { organization.owner }
  let(:server) { create(:server, organization: organization) }
  let(:importer) { described_class.new(server, owner, organization: organization) }

  before do
    create(:organization_membership, user: owner, organization: organization, role: :owner)
    allow(DeploymentJob).to receive(:perform_later)
  end

  def sample_container(attrs = {})
    {
      id: "abc123",
      name: "web-app",
      image: "myapp/web:latest",
      status: "running",
      running: true,
      created: Time.current.iso8601,
      command: "node server.js",
      ports: [
        { container_port: "3000", host_port: "8080", host_ip: "0.0.0.0" }
      ],
      env: { "PORT" => "3000", "NODE_ENV" => "production" },
      mounts: [
        { source: "/data/uploads", destination: "/app/uploads", type: "bind", mode: "rw" }
      ],
      labels: {},
      service_type: "app",
      subtype: nil
    }.merge(attrs)
  end

  describe "#import" do
    it "creates a project and services from containers" do
      result = importer.import([sample_container])

      expect(result[:success]).to be true
      expect(result[:project_name]).to eq("Imported Containers")

      project = Project.find(result[:project_id])
      expect(project.organization).to eq(organization)
      expect(project.server).to eq(server)

      service = project.services.first
      expect(service.name).to eq("web-app")
      expect(service.docker_image).to eq("myapp/web:latest")
      expect(service.port).to eq(3000)
      expect(service.environment_variables.pluck(:key)).to contain_exactly("PORT", "NODE_ENV")
      expect(service.storage_mounts.first.host_path).to eq("/data/uploads")

      expect(DeploymentJob).to have_received(:perform_later).with(service.id, instance_of(Integer))
    end

    it "can import into an existing project" do
      project = create(:project, organization: organization, server: server)
      result = importer.import([sample_container], project: project)

      expect(result[:project_id]).to eq(project.id)
      expect(project.services.count).to eq(1)
    end

    it "sanitizes container names" do
      result = importer.import([sample_container(name: "My Bad Name!!")])
      service = Project.find(result[:project_id]).services.first
      expect(service.name).to eq("my-bad-name")
    end

    it "deduplicates service names within the project" do
      project = create(:project, organization: organization, server: server)
      create(:service, project: project, name: "web-app")

      result = importer.import([sample_container], project: project)
      names = project.services.pluck(:name)
      expect(names).to include("web-app", "web-app-2")
    end

    it "reports failures for individual containers without aborting" do
      result = importer.import([sample_container(name: "", image: "")])
      expect(result[:success]).to be false
      expect(result[:results].first[:success]).to be false
    end
  end
end
