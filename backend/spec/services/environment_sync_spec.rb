require "rails_helper"

RSpec.describe EnvironmentSync do
  let(:project) { create(:project) }
  let(:production) { project.default_environment }
  let(:staging) { project.environments.create!(name: "staging") }

  subject(:result) { described_class.new(source: production, target: staging).call }

  describe "adding" do
    let!(:web) do
      create(:service, project: project, environment: production, name: "web", branch: "main")
    end
    let!(:db) { create(:service, :database, project: project, environment: production, name: "db") }
    let!(:volume) { create(:storage_mount, :volume, service: db, container_path: "/var/lib/postgresql/data") }
    let!(:variable) { create(:environment_variable, service: web, key: "API_URL", value: "https://api.example.com") }
    let!(:link) { ServiceLink.create!(from_service: web, to_service: db) }

    it "copies a service the target is missing" do
      expect { result }.to change { staging.services.count }.by(2)

      copy = staging.services.find_by(name: "web")
      expect(copy.status).to eq("stopped")
      expect(copy.branch).to eq("main")
      expect(copy.environment_variables.find_by(key: "API_URL").value).to eq("https://api.example.com")
    end

    it "gives the added service its own volume" do
      result

      copied_db = staging.services.find_by(name: "db")
      expect(copied_db.storage_mounts.sole.host_path).to eq("#{copied_db.dokku_app_name}-var-lib-postgresql-data")
      expect(copied_db.storage_mounts.sole.host_path).not_to eq(volume.host_path)
    end

    it "recreates links between the services it added" do
      result

      expect(staging.services.find_by(name: "web").linked_services)
        .to eq([ staging.services.find_by(name: "db") ])
    end

    it "reports what it added" do
      expect(result.message).to eq("2 added")
      expect(result.added.map(&:name)).to contain_exactly("web", "db")
    end

    it "records the sync as an activity event" do
      expect { result }.to change(ActivityEvent, :count).by(1)
      expect(ActivityEvent.last.message).to match(/Synced staging from production: 2 added/)
    end
  end

  describe "updating" do
    let!(:source_service) do
      create(:service, project: project, environment: production, name: "web", branch: "main")
    end
    let!(:target_service) do
      create(:service, project: project, environment: staging, name: "web", branch: "develop")
    end

    it "makes the drifted target match the source" do
      expect { result }.to change { target_service.reload.branch }.from("develop").to("main")
      expect(result.updated.map(&:name)).to eq([ "web" ])
    end

    it "adds a variable the target is missing and refreshes one that changed" do
      create(:environment_variable, service: source_service, key: "API_URL", value: "https://api.example.com")
      create(:environment_variable, service: source_service, key: "LOG_LEVEL", value: "info")
      create(:environment_variable, service: target_service, key: "LOG_LEVEL", value: "debug")

      result

      expect(target_service.environment_variables.find_by(key: "API_URL").value).to eq("https://api.example.com")
      expect(target_service.environment_variables.find_by(key: "LOG_LEVEL").value).to eq("info")
    end

    # Sync is additive on purpose: a staging-only variable, mount or schedule is
    # a deliberate difference, not drift to be cleaned up.
    it "never deletes a variable the target has and the source does not" do
      create(:environment_variable, service: target_service, key: "STAGING_ONLY", value: "1")

      result

      expect(target_service.environment_variables.find_by(key: "STAGING_ONLY")).to be_present
    end

    it "merges build settings instead of replacing them" do
      source_service.update!(config: { "staticSite" => { "publishDirectory" => "dist" } })
      target_service.update!(config: { "dockerfilePath" => "Dockerfile.web" })

      result

      expect(target_service.reload.config["dockerfilePath"]).to eq("Dockerfile.web")
      expect(target_service.config["staticSite"]).to eq({ "publishDirectory" => "dist" })
    end

    it "adds a mount the target is missing without touching the ones it has" do
      create(:storage_mount, :volume, service: source_service, container_path: "/app/data")
      own_mount = create(:storage_mount, service: target_service, kind: "bind", container_path: "/app/local", host_path: "/srv/local")

      result

      expect(target_service.storage_mounts.find_by(container_path: "/app/data")).to be_kind_volume
      expect(target_service.storage_mounts.find_by(container_path: "/app/local")).to eq(own_mount)
    end

    it "adds a backup schedule the target is missing" do
      mount = create(:storage_mount, :volume, service: source_service, container_path: "/app/data")
      source_service.backup_schedules.create!(backup_kind: "volume", frequency: "weekly", retention_count: 4, storage_mount: mount)

      result

      copied = target_service.storage_mounts.find_by(container_path: "/app/data")
      schedule = target_service.backup_schedules.sole
      expect(schedule.frequency).to eq("weekly")
      expect(schedule.storage_mount).to eq(copied)
      expect(schedule.next_run_at).to be_present
    end
  end

  describe "removals" do
    let!(:staging_only) do
      create(:service, project: project, environment: staging, name: "staging-worker")
    end

    # A service can own a database, a volume and backup artifacts, so the only
    # sanctioned way to remove one is the guarded destroy endpoint that snapshots
    # first. Sync must never become a back door around it.
    it "reports a service the source does not have without deleting it" do
      expect { result }.not_to change { staging.services.count }

      expect(result.removed.map(&:name)).to eq([ "staging-worker" ])
      expect(result.message).to eq("1 left alone (sync never deletes)")
      expect(staging_only.reload).to be_persisted
    end

    it "does not delete a service when the environments are otherwise identical" do
      create(:service, project: project, environment: production, name: "staging-worker")

      expect { result }.not_to change(Service, :count)
    end
  end

  describe "when nothing differs" do
    let!(:source_service) { create(:service, project: project, environment: production, name: "web") }
    let!(:target_service) { create(:service, project: project, environment: staging, name: "web") }

    it "writes nothing and says so" do
      expect { result }.not_to change(ActivityEvent, :count)
      expect(result.message).to eq("Already in sync with production.")
      expect(result.updated).to be_empty
    end
  end
end
