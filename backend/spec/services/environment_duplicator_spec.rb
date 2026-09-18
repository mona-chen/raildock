require "rails_helper"

RSpec.describe EnvironmentDuplicator do
  let(:project) { create(:project) }
  let(:production) { project.default_environment }

  let!(:web) do
    create(:service, project: project, environment: production, name: "web", branch: "main",
      config: { "staticSite" => { "publishDirectory" => "dist" } })
  end
  let!(:db) { create(:service, :database, project: project, environment: production, name: "db") }

  let!(:web_url) do
    create(:environment_variable, service: web, key: "API_URL", value: "https://api.example.com", source: "ui")
  end
  # StorageMountEnvSync owns these; they are regenerated from the copied mounts.
  let!(:storage_var) do
    create(:environment_variable, service: web, key: "RAILDOCK_STORAGE_HOST", value: "old-volume",
      source: "raildock-storage", is_dokku_internal: true)
  end
  let!(:volume) do
    create(:storage_mount, :volume, service: web, container_path: "/app/data", host_path: "#{web.dokku_app_name}-app-data")
  end
  let!(:schedule) do
    web.backup_schedules.create!(backup_kind: "volume", frequency: "daily", retention_count: 3,
      storage_mount: volume, metadata: { "destination_ids" => [ 7 ] })
  end
  let!(:link) { ServiceLink.create!(from_service: web, to_service: db) }
  let!(:custom_domain) { create(:domain, service: web, hostname: "app.example.com", temporary: false) }
  let!(:temporary_domain) do
    create(:domain, service: web, hostname: "#{web.dokku_app_name}.203.0.113.7.sslip.io", temporary: true)
  end

  subject(:result) { described_class.new(production, name: "staging").call }

  it "creates a new environment in the same project" do
    expect { result }.to change { project.environments.count }.by(1)

    expect(result.environment.name).to eq("staging")
    expect(result.environment).not_to be_default
    expect(result.environment.project).to eq(project)
  end

  it "copies every service as a stopped, never-deployed copy" do
    copies = result.environment.services.reload

    expect(copies.map(&:name)).to contain_exactly("web", "db")
    expect(copies.map(&:status).uniq).to eq([ "stopped" ])
    expect(copies.map(&:last_deployed).uniq).to eq([ nil ])
    expect(copies.flat_map(&:deployments)).to be_empty
  end

  # A duplicate that carried the original app name would collide on the Dokku
  # host: `Service#generate_dokku_app_name` only fills a *nil* attribute.
  it "gives every copy its own Dokku app name and webhook token" do
    copies = result.environment.services.reload
    originals = [ web, db ]

    expect(copies.map(&:dokku_app_name)).to all(be_present)
    expect(copies.map(&:dokku_app_name) & originals.map(&:dokku_app_name)).to be_empty
    expect(copies.map(&:dokku_app_name).uniq.size).to eq(2)
    expect(copies.map(&:webhook_token) & originals.map(&:webhook_token)).to be_empty
  end

  it "carries build configuration and operator variables, but not internal ones" do
    copy = result.environment.services.find_by(name: "web")

    expect(copy.config).to eq(web.config)
    expect(copy.branch).to eq("main")
    expect(copy.environment_variables.pluck(:key)).to eq([ "API_URL" ])
    expect(copy.environment_variables.find_by(key: "API_URL").value).to eq("https://api.example.com")
    expect(copy.environment_variables.find_by(key: "API_URL").source).to eq("ui")
  end

  it "keeps the canvas layout so the copy looks like the environment it came from" do
    web.update!(canvas_x: 120, canvas_y: 340)

    expect(result.environment.services.find_by(name: "web").canvas_x).to eq(120)
    expect(result.environment.services.find_by(name: "web").canvas_y).to eq(340)
  end

  describe "storage" do
    it "gives a copied volume its own name instead of sharing the original's" do
      copy = result.environment.services.find_by(name: "web")
      copied_mount = copy.storage_mounts.sole

      expect(copied_mount.container_path).to eq("/app/data")
      expect(copied_mount.host_path).to eq("#{copy.dokku_app_name}-app-data")
      expect(copied_mount.host_path).not_to eq(volume.host_path)
    end

    it "reports bind mounts that end up sharing a host directory" do
      create(:storage_mount, service: web, kind: "bind", container_path: "/app/uploads", host_path: "/srv/uploads")

      expect(result.summary[:bind_mounts]).to eq(1)
      expect(result.summary[:warnings].join).to match(/bind mount point at the same host path/)
    end
  end

  describe "backup schedules" do
    it "remaps a volume schedule to the copy's own mount" do
      copy = result.environment.services.find_by(name: "web")
      copied = copy.backup_schedules.sole

      expect(copied.frequency).to eq("daily")
      expect(copied.retention_count).to eq(3)
      expect(copied.storage_mount).to eq(copy.storage_mounts.sole)
      expect(copied.next_run_at).to be_present
      expect(copied.metadata["destination_ids"]).to eq([ 7 ])
      # `schedule_id` is stamped on the artifacts a schedule produces; inheriting
      # it would make retention count the original's backups.
      expect(copied.metadata).not_to have_key("schedule_id")
    end

    it "copies a paused schedule as paused" do
      schedule.update!(enabled: false)

      expect(result.environment.services.find_by(name: "web").backup_schedules.sole).not_to be_enabled
    end
  end

  describe "links" do
    it "recreates a link between two services that were both copied" do
      copies = result.environment.services.reload
      copy_web = copies.find { |service| service.name == "web" }
      copy_db = copies.find { |service| service.name == "db" }

      expect(copy_web.linked_services).to eq([ copy_db ])
    end

    it "drops a link whose other end was not copied" do
      outside = create(:service, project: create(:project), name: "outside")
      ServiceLink.create!(from_service: web, to_service: outside)

      copy_web = result.environment.services.find_by(name: "web")

      expect(copy_web.linked_services.map(&:name)).to eq([ "db" ])
      expect(ServiceLink.count).to eq(3)
    end

    it "counts the links it recreated" do
      expect(result.summary[:links]).to eq(1)
    end
  end

  describe "domains" do
    it "does not copy a custom domain, because two apps cannot own one hostname" do
      copy = result.environment.services.find_by(name: "web")

      expect(copy.domains.pluck(:hostname)).not_to include("app.example.com")
      expect(result.summary[:domains_skipped]).to eq(1)
      expect(result.summary[:warnings].join).to match(/1 custom domain was not copied/)
    end

    it "gives a publicly reachable service its own temporary hostname" do
      copy = result.environment.services.find_by(name: "web")
      copied = copy.domains.find(&:temporary?)

      expect(copied).to be_present
      expect(copied.hostname).to include(copy.dokku_app_name)
      expect(copied.hostname).not_to eq(temporary_domain.hostname)
    end
  end

  it "reports what it staged" do
    summary = result.summary

    expect(summary[:services]).to eq(2)
    expect(summary[:variables]).to eq(1)
    expect(summary[:volumes]).to eq(1)
    expect(summary[:schedules]).to eq(1)
    expect(summary[:process_types]).to eq(0)
  end

  it "records the duplication as an activity event" do
    expect { result }.to change(ActivityEvent, :count).by(1)
    expect(ActivityEvent.last.message).to match(/Duplicated production into staging/)
  end

  it "refuses a blank name without creating an environment" do
    result = described_class.new(production, name: "  ").call

    expect(result.environment).to be_nil
    expect(result.summary[:warnings]).to eq([ "An environment name is required." ])
  end

  it "rejects a name another environment in the project already uses" do
    project.environments.create!(name: "staging")

    expect { result }.to raise_error(ActiveRecord::RecordInvalid)
  end
end
