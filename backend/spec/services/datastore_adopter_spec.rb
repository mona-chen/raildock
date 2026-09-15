require "rails_helper"

RSpec.describe DatastoreAdopter do
  let(:organization) { create(:organization) }
  let(:server) { create(:server, organization: organization) }
  let(:project) { create(:project, name: "tween", server: server) }
  let(:user) { create(:user) }
  let(:scanner) { instance_double(UnmanagedDatastoreScanner) }
  let(:adopter) { described_class.new(server, user: user, scanner: scanner) }

  let(:resource) do
    {
      name: "tween-jean-postgres",
      subtype: "postgres",
      service_type: "database",
      status: "running",
      linked_apps: [ "tween-jean-646e2ba9" ]
    }
  end

  before do
    allow(scanner).to receive(:scan).and_return(success: true, resources: [ resource ], errors: [])
  end

  def adopt(name: "tween-jean-postgres", target_project: project)
    adopter.adopt!(resource_name: name, project: target_project)
  end

  it "records the running datastore under the project" do
    service = adopt

    expect(service.project).to eq(project)
    expect(service.name).to eq("jean-postgres")
    expect(service.dokku_app_name).to eq("tween-jean-postgres")
    expect(service.subtype).to eq("postgres")
    expect(service.service_type).to eq("database")
    expect(service.status).to eq("running")
  end

  it "adopts as UI-managed so manifest reconciliation can never remove it" do
    expect(adopt.managed_by).to eq("ui")
  end

  it "keeps the provenance of the adopted resource" do
    config = adopt.config

    expect(config["adopted"]).to be true
    expect(config["host_resource"]).to eq("tween-jean-postgres")
    expect(config["host_status"]).to eq("running")
    expect(config["host_linked_apps"]).to eq([ "tween-jean-646e2ba9" ])
    expect(config["adopted_by_user_id"]).to eq(user.id)
    expect(config["adopted_at"]).to be_present
  end

  it "never provisions anything on the host" do
    # Adoption is bookkeeping only: no dokku create, no engine connection at all.
    expect(DokkuEngine).not_to receive(:new)

    adopt
  end

  it "records the adoption in the project activity feed" do
    expect { adopt }.to change(ActivityEvent, :count).by(1)

    event = ActivityEvent.last
    expect(event.action).to eq("created")
    expect(event.message).to include("tween-jean-postgres")
    expect(event.metadata["adopted"]).to be true
  end

  it "takes an explicit service name when one is given" do
    expect(adopter.adopt!(resource_name: "tween-jean-postgres", project: project, name: "jean-main-db").name)
      .to eq("jean-main-db")
  end

  it "does not collide with an existing service name" do
    create(:service, :database, project: project, name: "jean-postgres", dokku_app_name: "tween-other")

    expect(adopt.name).to eq("jean-postgres-2")
  end

  it "marks a datastore Dokku reports as stopped" do
    allow(scanner).to receive(:scan).and_return(success: true, resources: [ resource.merge(status: "stopped") ], errors: [])

    expect(adopt.status).to eq("stopped")
  end

  it "records the links the host already has" do
    app = create(:service, project: project, dokku_app_name: "tween-jean-646e2ba9")

    expect { adopt }.to change(ServiceLink, :count).by(1)

    link = ServiceLink.last
    expect(link.from_service).to eq(app)
    expect(link.to_service.dokku_app_name).to eq("tween-jean-postgres")
  end

  it "does not invent links for apps RailDock does not track" do
    expect { adopt }.not_to change(ServiceLink, :count)
  end

  it "links every adopted datastore to the app once, and refuses a double adoption" do
    app = create(:service, project: project, dokku_app_name: "tween-jean-646e2ba9")
    cache = { name: "tween-jean-redis", subtype: "redis", service_type: "cache", status: "running",
              linked_apps: [ "tween-jean-646e2ba9" ] }
    allow(scanner).to receive(:scan).and_return(success: true, resources: [ resource, cache ], errors: [])

    adopt
    adopter.adopt!(resource_name: "tween-jean-redis", project: project)

    expect(ServiceLink.where(from_service: app).count).to eq(2)
    postgres = project.services.find_by(dokku_app_name: "tween-jean-postgres")
    expect(ServiceLink.where(from_service: app, to_service: postgres).count).to eq(1)

    expect { adopter.adopt!(resource_name: "tween-jean-redis", project: project) }
      .to raise_error(DatastoreAdopter::NotAdoptable, /already tracked/)
    expect(ServiceLink.where(from_service: app).count).to eq(2)
  end

  it "refuses a name that is already tracked" do
    allow(scanner).to receive(:scan).and_return(success: true, resources: [], errors: [])
    create(:service, :database, project: project, dokku_app_name: "tween-jean-postgres")

    expect { adopt }.to raise_error(DatastoreAdopter::NotAdoptable, /already tracked/)
  end

  it "refuses a resource the host does not have" do
    allow(scanner).to receive(:scan).and_return(success: true, resources: [], errors: [])

    expect { adopt(name: "not-there") }.to raise_error(DatastoreAdopter::NotAdoptable, /not found/)
  end

  it "refuses a project that lives on another server" do
    other_project = create(:project, server: create(:server, organization: organization))

    expect { adopt(target_project: other_project) }
      .to raise_error(DatastoreAdopter::NotAdoptable, /different server/)
  end

  it "refuses a blank resource name" do
    expect { adopt(name: "  ") }.to raise_error(DatastoreAdopter::NotAdoptable, /required/)
  end

  it "surfaces a scan failure instead of adopting nothing silently" do
    allow(scanner).to receive(:scan).and_return(success: false, error: "ssh refused", resources: [], errors: [])

    expect { adopt }.to raise_error(DatastoreAdopter::NotAdoptable, "ssh refused")
  end
end
