require "rails_helper"

RSpec.describe EnvironmentDiff do
  let(:project) { create(:project) }
  let(:production) { project.default_environment }
  let(:staging) { project.environments.create!(name: "staging") }

  def diff
    described_class.new(source: production, target: staging).call
  end

  it "lists a service the target is missing as added" do
    service = create(:service, project: project, environment: production, name: "web")

    plan = diff

    expect(plan.added.map(&:name)).to eq([ "web" ])
    expect(plan.added.first.service_id).to eq(service.id)
    expect(plan).to be_changes
  end

  it "lists a service the source is missing as removed" do
    create(:service, project: project, environment: staging, name: "old-worker")

    expect(diff.removed.map(&:name)).to eq([ "old-worker" ])
  end

  it "reports nothing when the environments match" do
    create(:service, project: project, environment: production, name: "web")
    create(:service, project: project, environment: staging, name: "web")

    plan = diff

    expect(plan).not_to be_changes
    expect(plan.as_json["summary"]["in_sync"]).to be(true)
  end

  describe "drift on a service both environments have" do
    before do
      @source = create(:service, project: project, environment: production, name: "web", branch: "main")
      @target = create(:service, project: project, environment: staging, name: "web", branch: "main")
    end

    it "names the differing fields" do
      @target.update!(branch: "develop")

      expect(diff.edited.map(&:name)).to eq([ "web" ])
      expect(diff.edited.first.changes).to include("branch")
    end

    it "names a differing variable without leaking its value" do
      create(:environment_variable, service: @source, key: "DATABASE_URL", value: "postgres://prod")
      create(:environment_variable, service: @target, key: "DATABASE_URL", value: "postgres://staging")
      create(:environment_variable, service: @source, key: "SECRET", value: "super-secret-value")

      entry = diff.edited.sole

      expect(entry.changes).to include("environment variable DATABASE_URL")
      expect(entry.changes).to include("environment variable SECRET")
      expect(entry.as_json.to_s).not_to include("super-secret-value")
      expect(entry.as_json.to_s).not_to include("postgres://prod")
    end

    # This is the difference between "sync" and "make these identical": a
    # staging-only variable is what an environment is *for*.
    it "ignores a variable the target has and the source does not" do
      create(:environment_variable, service: @target, key: "STAGING_ONLY", value: "1")

      expect(diff).not_to be_changes
    end

    it "ignores an extra build setting the target carries" do
      @source.update!(config: { "staticSite" => { "publishDirectory" => "dist" } })
      @target.update!(config: { "staticSite" => { "publishDirectory" => "dist" }, "dockerfilePath" => "Dockerfile.web" })

      expect(diff).not_to be_changes
    end

    # Volume *names* are per service, so comparing them would report permanent
    # drift on every service with a volume.
    it "treats a volume named for its own service as the same mount" do
      create(:storage_mount, :volume, service: @source, container_path: "/app/data", host_path: "#{@source.dokku_app_name}-app-data")
      create(:storage_mount, :volume, service: @target, container_path: "/app/data", host_path: "#{@target.dokku_app_name}-app-data")

      expect(diff).not_to be_changes
    end

    it "reports a missing link by the name of the service it points at" do
      other_source = create(:service, project: project, environment: production, name: "db")
      create(:service, project: project, environment: staging, name: "db")
      ServiceLink.create!(from_service: @source, to_service: other_source)

      expect(diff.edited.sole.changes).to include("link to db")
    end

    it "reports a differing backup schedule" do
      mount = create(:storage_mount, :volume, service: @source, container_path: "/app/data")
      @source.backup_schedules.create!(backup_kind: "volume", frequency: "daily", retention_count: 7, storage_mount: mount)

      expect(diff.edited.sole.changes).to include("backup schedule (volume)")
    end
  end
end
