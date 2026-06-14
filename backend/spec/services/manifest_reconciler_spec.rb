require "rails_helper"

RSpec.describe ManifestReconciler do
  let(:server) { create(:server) }
  let(:project) { create(:project, server: server) }

  def desired_state(services:, links: [])
    ManifestParser::ManifestDesiredState.new(
      services: services,
      links: links,
      format_detected: "raildock.toml"
    )
  end

  def app_definition(name:, repo:, branch: "main", builder: "nixpacks")
    {
      name: name,
      category: "app",
      subtype: "web",
      builder: builder,
      source: { type: "git", repo: repo, branch: branch },
      env: {},
      domains: [],
      storage: [],
      proxy: {},
      scaling: {},
      limits: {},
      reservations: {},
      checks: {},
      cron: [],
      docker_options: [],
      traefik_labels: {},
      letsencrypt: {},
      maintenance: false,
      depends_on: []
    }
  end

  describe "#diff" do
    it "includes explicitly listed UI-managed services" do
      create(
        :service,
        project: project,
        name: "web",
        managed_by: :ui,
        git_repo: "https://github.com/acme/app.git",
        branch: "main",
        builder: "nixpacks"
      )
      definition = app_definition(name: "web", repo: "https://github.com/acme/app.git")
      definition[:port] = 3000

      changes = described_class.new(project, desired_state(services: [ definition ])).diff

      expect(changes).to include(have_attributes(service_name: "web", field: :port, new_value: 3000))
    end

    it "detects changes using the normalized symbol-keyed desired state" do
      create(
        :service,
        project: project,
        name: "web",
        managed_by: :manifest,
        git_repo: "https://github.com/acme/app.git",
        branch: "main",
        builder: "nixpacks"
      )

      desired = desired_state(
        services: [
          app_definition(
            name: "web",
            repo: "https://github.com/acme/app.git",
            branch: "production",
            builder: "dockerfile"
          )
        ]
      )

      changes = described_class.new(project, desired).diff

      expect(changes.map { |change| [ change.field, change.new_value ] }).to include(
        [ :branch, "production" ],
        [ :builder, "dockerfile" ]
      )
    end

    it "preserves link direction" do
      create(:service, project: project, name: "web", managed_by: :manifest)
      create(:service, :database, project: project, name: "postgres", managed_by: :manifest)

      desired = desired_state(
        services: [
          app_definition(name: "web", repo: "https://github.com/acme/app.git"),
          {
            name: "postgres",
            category: "database",
            subtype: "postgres",
            source: { type: "git", branch: "main" },
            env: {},
            domains: [],
            storage: [],
            proxy: {},
            scaling: {},
            limits: {},
            reservations: {},
            checks: {},
            cron: [],
            docker_options: [],
            traefik_labels: {},
            letsencrypt: {},
            maintenance: false,
            depends_on: []
          }
        ],
        links: [ { from: "web", to: "postgres" } ]
      )

      link_change = described_class.new(project, desired).diff.find { |change| change.field == :link }

      expect(link_change.new_value).to eq(from: "web", to: "postgres")
    end

    it "does not report drift when shared variables resolve to the current value" do
      project.update!(shared_vars: [ { key: "API_KEY", value: "secret" } ])
      service = create(
        :service,
        project: project,
        name: "web",
        managed_by: :manifest,
        git_repo: "https://github.com/acme/app.git",
        branch: "main",
        builder: "nixpacks"
      )
      service.environment_variables.create!(key: "API_KEY", value: "secret")
      definition = app_definition(name: "web", repo: "https://github.com/acme/app.git")
      definition[:env] = { "API_KEY" => "[SHARED:API_KEY]" }

      changes = described_class.new(project, desired_state(services: [ definition ])).diff

      expect(changes).not_to include(have_attributes(field: :env))
    end

    it "ignores Dokku-internal variables when comparing manifest env" do
      service = create(
        :service,
        project: project,
        name: "web",
        managed_by: :manifest,
        git_repo: "https://github.com/acme/app.git",
        branch: "main",
        builder: "nixpacks"
      )
      service.environment_variables.create!(
        key: "DATABASE_URL",
        value: "postgres://internal",
        is_dokku_internal: true
      )

      changes = described_class.new(
        project,
        desired_state(services: [ app_definition(name: "web", repo: "https://github.com/acme/app.git") ])
      ).diff

      expect(changes).not_to include(have_attributes(field: :env))
    end

    it "does not diff HTTP proxy fields for database services" do
      create(
        :service,
        :database,
        project: project,
        name: "postgres",
        managed_by: :manifest,
        config: { "proxy" => { "enabled" => true } }
      )
      definition = {
        name: "postgres",
        category: "database",
        subtype: "postgres",
        version: "16",
        source: { type: "git", branch: "main" },
        env: {},
        domains: [],
        storage: [],
        proxy: {},
        scaling: {},
        limits: {},
        reservations: {},
        checks: {},
        cron: [],
        docker_options: [],
        traefik_labels: {},
        letsencrypt: {},
        maintenance: false,
        depends_on: []
      }

      changes = described_class.new(project, desired_state(services: [ definition ])).diff

      expect(changes).not_to include(have_attributes(field: :proxy))
    end
  end

  describe "#apply!" do
    it "adopts explicitly listed UI-managed services into manifest management" do
      service = create(
        :service,
        project: project,
        name: "web",
        managed_by: :ui,
        git_repo: "https://github.com/acme/app.git",
        branch: "main",
        builder: "nixpacks"
      )
      reconciler = described_class.new(
        project,
        desired_state(services: [ app_definition(name: "web", repo: "https://github.com/acme/app.git") ])
      )
      reconciler.diff

      result = reconciler.apply!(instance_double(DokkuEngine), host_engine: instance_double(HostEngine))

      expect(result[:success]).to be(true)
      expect(service.reload).to be_managed_by_manifest
    end

    it "queues an app that was created previously but has never deployed successfully" do
      service = create(
        :service,
        project: project,
        name: "web",
        managed_by: :manifest,
        git_repo: "https://github.com/acme/app.git",
        branch: "main",
        builder: "nixpacks",
        status: :error
      )
      reconciler = described_class.new(
        project,
        desired_state(services: [ app_definition(name: "web", repo: "https://github.com/acme/app.git") ])
      )
      reconciler.diff
      allow(DeploymentSequenceJob).to receive(:perform_later)

      result = reconciler.apply!(instance_double(DokkuEngine), host_engine: instance_double(HostEngine))

      expect(result[:success]).to be(true)
      expect(service.deployments.pending.count).to eq(1)
      expect(DeploymentSequenceJob).to have_received(:perform_later).once
    end

    it "creates manifest domains with valid proxy ports" do
      definition = app_definition(name: "web", repo: "https://github.com/acme/app.git")
      definition[:port] = 3000
      definition[:domains] = [ "app.example.com" ]
      reconciler = described_class.new(project, desired_state(services: [ definition ]))
      reconciler.diff
      engine = instance_double(DokkuEngine)
      host_engine = instance_double(HostEngine)

      allow(engine).to receive(:app_create).and_return(success: true)
      allow(engine).to receive(:proxy_set).and_return(success: true)
      allow(DeploymentSequenceJob).to receive(:perform_later)

      result = reconciler.apply!(engine, host_engine: host_engine)

      domain = project.services.find_by!(name: "web").domains.find_by!(hostname: "app.example.com")
      expect(result[:success]).to be(true)
      expect(domain).to have_attributes(port: 443, target_port: 3000, ssl: true, letsencrypt: true)
    end

    it "creates a directed Dokku database link before persisting the link record" do
      web = create(:service, project: project, name: "web", managed_by: :manifest)
      postgres = create(:service, :database, project: project, name: "postgres", managed_by: :manifest)
      reconciler = described_class.new(project, desired_state(services: [], links: []))
      engine = instance_double(DokkuEngine)
      host_engine = instance_double(HostEngine)
      change = described_class::Change.new(
        service_name: "web->postgres",
        field: :link,
        change_type: :added,
        old_value: nil,
        new_value: { from: "web", to: "postgres" }
      )

      reconciler.instance_variable_set(:@host_engine, host_engine)
      reconciler.instance_variable_set(:@engine, engine)
      allow(engine).to receive(:network_list).and_return(success: true, output: project.network_name)
      allow(engine).to receive(:postgres_link).and_return(success: true, output: "")
      allow(engine).to receive(:config_set).and_return(success: true, output: "")
      allow(engine).to receive(:config_show).and_return(
        success: true,
        output: "DATABASE_URL=postgres://user:password@postgres:5432/app"
      )
      allow(host_engine).to receive(:dokku_container_name).and_return(nil)

      result = reconciler.send(:apply_link_change, engine, change)

      expect(result[:success]).to be(true)
      expect(engine).to have_received(:postgres_link).with(postgres.dokku_app_name, web.dokku_app_name)
      expect(ServiceLink.exists?(from_service: web, to_service: postgres)).to be(true)
      expect(web.environment_variables.find_by(key: "DATABASE_URL")&.value).to start_with("postgres://")
    end

    it "leaves a failed Dokku link retryable" do
      web = create(:service, project: project, name: "web", managed_by: :manifest)
      postgres = create(:service, :database, project: project, name: "postgres", managed_by: :manifest)
      reconciler = described_class.new(project, desired_state(services: [], links: []))
      engine = instance_double(DokkuEngine)
      change = described_class::Change.new(
        service_name: "web->postgres",
        field: :link,
        change_type: :added,
        old_value: nil,
        new_value: { from: "web", to: "postgres" }
      )

      allow(engine).to receive(:postgres_link).and_return(success: false, output: "link failed")

      result = reconciler.send(:apply_link_change, engine, change)

      expect(result[:success]).to be(false)
      expect(ServiceLink.exists?(from_service: web, to_service: postgres)).to be(false)
    end

    it "queues one deployment after applying all redeploy changes for a service" do
      service = create(
        :service,
        project: project,
        name: "web",
        managed_by: :manifest,
        git_repo: "https://github.com/acme/app.git",
        branch: "main",
        builder: "nixpacks"
      )
      desired = desired_state(
        services: [
          app_definition(
            name: "web",
            repo: "https://github.com/acme/app.git",
            branch: "production",
            builder: "dockerfile"
          )
        ]
      )
      reconciler = described_class.new(project, desired)
      reconciler.diff
      engine = instance_double(DokkuEngine)
      host_engine = instance_double(HostEngine)

      allow(DeploymentSequenceJob).to receive(:perform_later)

      result = reconciler.apply!(engine, host_engine: host_engine)

      expect(result[:success]).to be(true)
      expect(service.reload).to have_attributes(branch: "production", builder: "dockerfile", status: "deploying")
      expect(service.deployments.pending.count).to eq(1)
      expect(DeploymentSequenceJob).to have_received(:perform_later).once
    end
  end
end
