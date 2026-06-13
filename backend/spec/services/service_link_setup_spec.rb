# frozen_string_literal: true

require "rails_helper"

RSpec.describe ServiceLinkSetup do
  let!(:server) { create(:server) }
  let!(:project) { create(:project, server: server) }
  let!(:app_service) do
    create(:service, project: project, name: "web", git_repo: "https://github.com/example/app.git")
  end
  let!(:db_service) do
    create(:service, :database, project: project, name: "postgres", subtype: "postgres")
  end
  let(:engine) { instance_double(DokkuEngine) }
  let(:host_engine) { instance_double(HostEngine) }
  let(:network_manager) do
    instance_double(ProjectNetworkManager,
      ensure_network!: true,
      connect_container_with_aliases: { success: true, output: "" })
  end
  let(:linker) { described_class.new(project, engine, host_engine: host_engine) }

  before do
    allow(ProjectNetworkManager).to receive(:new).with(project, engine).and_return(network_manager)
  end

  # ── setup! ──────────────────────────────────────────────

  describe "#setup!" do
    before do
      allow(engine).to receive(:config_show).and_return(
        success: true,
        output: "DATABASE_URL=postgres://user:password@dokku-postgres-web:5432/app"
      )
      allow(engine).to receive(:postgres_info).and_return(
        success: true,
        dsn: "postgres://realuser:realpass@dokku-postgres-web:5432/realdb",
        status: "running"
      )
      allow(engine).to receive(:config_set).and_return(success: true, output: "")
    end

    it "sets PGSSLMODE for postgres links" do
      result = linker.setup!(app_service, db_service)

      expect(result[:success]).to be(true)
      expect(engine).to have_received(:config_set).with(app_service.dokku_app_name, "PGSSLMODE", "disable")
      expect(app_service.environment_variables.find_by(key: "PGSSLMODE")&.value).to eq("disable")
    end

    it "skips PGSSLMODE for non-postgres links" do
      mysql_service = create(:service, :database, project: project, name: "mysql", subtype: "mysql")

      allow(engine).to receive(:mysql_info).and_return(
        success: true,
        dsn: "mysql://realuser:realpass@dokku-mysql-web:3306/realdb",
        status: "running"
      )

      linker.setup!(app_service, mysql_service)

      expect(engine).not_to have_received(:config_set).with(app_service.dokku_app_name, "PGSSLMODE", "disable")
    end

    it "returns failure when PGSSLMODE config_set fails" do
      allow(engine).to receive(:config_set).with(app_service.dokku_app_name, "PGSSLMODE", "disable")
        .and_return(success: false, output: "permission denied")

      result = linker.setup!(app_service, db_service)

      expect(result[:success]).to be(false)
      expect(result[:error]).to eq("permission denied")
    end

    it "calls sync_env_vars and rewrite_from_dsn" do
      result = linker.setup!(app_service, db_service)

      expect(result[:success]).to be(true)
      expect(engine).to have_received(:config_show).with(app_service.dokku_app_name)
      expect(engine).to have_received(:postgres_info).with(db_service.dokku_app_name)
    end

    it "returns failure when sync_env_vars fails" do
      allow(engine).to receive(:config_show).and_return(success: false, output: "app not found")

      result = linker.setup!(app_service, db_service)

      expect(result[:success]).to be(false)
      expect(result[:error]).to eq("app not found")
    end

    it "returns failure when rewrite_from_dsn fails" do
      allow(engine).to receive(:postgres_info).and_return(success: false, dsn: nil)

      result = linker.setup!(app_service, db_service)

      expect(result[:success]).to be(false)
    end

    it "rewrites DATABASE_URL from the _info DSN" do
      linker.setup!(app_service, db_service)

      expect(engine).to have_received(:config_set).with(
        app_service.dokku_app_name, "DATABASE_URL", "postgres://realuser:realpass@dokku-postgres-web:5432/realdb"
      )
      ev = app_service.environment_variables.find_by(key: "DATABASE_URL")
      expect(ev&.value).to eq("postgres://realuser:realpass@dokku-postgres-web:5432/realdb")
      expect(ev&.source).to eq("dokku-link")
    end
  end

  # ── sync_env_vars ───────────────────────────────────────

  describe "#sync_env_vars" do
    it "persists injected DATABASE_URL from config_show" do
      allow(engine).to receive(:config_show).and_return(
        success: true,
        output: "DATABASE_URL=postgres://user:password@dokku-postgres-web:5432/app"
      )

      result = linker.sync_env_vars(app_service, db_service)

      expect(result[:success]).to be(true)
      ev = app_service.environment_variables.find_by(key: "DATABASE_URL")
      expect(ev).to be_present
      expect(ev.value).to eq("postgres://user:password@dokku-postgres-web:5432/app")
      expect(ev.is_dokku_internal).to be(true)
      expect(ev.source).to eq("dokku-link")
    end

    it "persists multiple URL vars from config_show" do
      allow(engine).to receive(:config_show).and_return(
        success: true,
        output: <<~OUTPUT
          DATABASE_URL=postgres://user:pass@host:5432/db
          DATABASE_PRIVATE_URL=postgres://user:pass@private:5432/db
          DOKKU_POSTGRES_PINK_URL=postgres://user:pass@dokku:5432/db
        OUTPUT
      )

      linker.sync_env_vars(app_service, db_service)

      expect(app_service.environment_variables.find_by(key: "DATABASE_URL")).to be_present
      expect(app_service.environment_variables.find_by(key: "DATABASE_PRIVATE_URL")).to be_present
      expect(app_service.environment_variables.find_by(key: "DOKKU_POSTGRES_PINK_URL")).to be_present
    end

    it "ignores blank values and shell variable references" do
      allow(engine).to receive(:config_show).and_return(
        success: true,
        output: <<~OUTPUT
          DATABASE_URL=
          DATABASE_PRIVATE_URL=$SOME_VAR
          MONGO_URL=mongodb://host/db
        OUTPUT
      )

      linker.sync_env_vars(app_service, db_service)

      expect(app_service.environment_variables.find_by(key: "DATABASE_URL")).not_to be_present
      expect(app_service.environment_variables.find_by(key: "DATABASE_PRIVATE_URL")).not_to be_present
      expect(app_service.environment_variables.find_by(key: "MONGO_URL")).to be_present
    end

    it "returns failure on config_show error" do
      allow(engine).to receive(:config_show).and_return(success: false, output: "timeout")

      result = linker.sync_env_vars(app_service, db_service)

      expect(result[:success]).to be(false)
      expect(result[:error]).to eq("timeout")
    end

    it "updates existing env vars when value changes" do
      app_service.environment_variables.create!(key: "DATABASE_URL", value: "old://url", source: "manual")
      allow(engine).to receive(:config_show).and_return(
        success: true,
        output: "DATABASE_URL=postgres://newuser:newpass@host:5432/newdb"
      )

      linker.sync_env_vars(app_service, db_service)

      ev = app_service.environment_variables.find_by(key: "DATABASE_URL")
      expect(ev.value).to eq("postgres://newuser:newpass@host:5432/newdb")
      expect(ev.source).to eq("dokku-link")
    end
  end

  # ── rewrite_from_dsn ────────────────────────────────────

  describe "#rewrite_from_dsn" do
    before do
      allow(engine).to receive(:postgres_info).and_return(
        success: true,
        dsn: "postgres://realuser:realpass@dokku-postgres-web:5432/realdb",
        status: "running"
      )
      allow(engine).to receive(:config_set).and_return(success: true, output: "")
    end

    it "overwrites DATABASE_URL with the real DSN" do
      linker.rewrite_from_dsn(app_service, db_service)

      expect(engine).to have_received(:config_set).with(
        app_service.dokku_app_name,
        "DATABASE_URL",
        "postgres://realuser:realpass@dokku-postgres-web:5432/realdb"
      )
    end

    it "rewrites DATABASE_HOST from service name to DSN host" do
      app_service.environment_variables.create!(key: "DATABASE_HOST", value: db_service.name)
      app_service.environment_variables.create!(key: "DATABASE_URL", value: "postgres://placeholder:pass@host:5432/db")

      linker.rewrite_from_dsn(app_service, db_service)

      expect(engine).to have_received(:config_set).with(
        app_service.dokku_app_name, "DATABASE_HOST", "dokku-postgres-web"
      )
      ev = app_service.environment_variables.find_by(key: "DATABASE_HOST")
      expect(ev.value).to eq("dokku-postgres-web")
    end

    it "rewrites DATABASE_USER from DSN" do
      app_service.environment_variables.create!(key: "DATABASE_USER", value: "placeholder")
      app_service.environment_variables.create!(key: "DATABASE_URL", value: "postgres://placeholder:pass@host:5432/db")

      linker.rewrite_from_dsn(app_service, db_service)

      expect(engine).to have_received(:config_set).with(
        app_service.dokku_app_name, "DATABASE_USER", "realuser"
      )
    end

    it "rewrites DATABASE_PASSWORD from DSN" do
      app_service.environment_variables.create!(key: "DATABASE_PASSWORD", value: "placeholder")
      app_service.environment_variables.create!(key: "DATABASE_URL", value: "postgres://placeholder:pass@host:5432/db")

      linker.rewrite_from_dsn(app_service, db_service)

      expect(engine).to have_received(:config_set).with(
        app_service.dokku_app_name, "DATABASE_PASSWORD", "realpass"
      )
    end

    it "rewrites DATABASE_PORT from DSN" do
      app_service.environment_variables.create!(key: "DATABASE_PORT", value: "0000")
      app_service.environment_variables.create!(key: "DATABASE_URL", value: "postgres://placeholder:pass@host:5432/db")

      linker.rewrite_from_dsn(app_service, db_service)

      expect(engine).to have_received(:config_set).with(
        app_service.dokku_app_name, "DATABASE_PORT", "5432"
      )
    end

    it "rewrites DATABASE_NAME from DSN" do
      app_service.environment_variables.create!(key: "DATABASE_NAME", value: "placeholder")
      app_service.environment_variables.create!(key: "DATABASE_URL", value: "postgres://placeholder:pass@host:5432/db")

      linker.rewrite_from_dsn(app_service, db_service)

      expect(engine).to have_received(:config_set).with(
        app_service.dokku_app_name, "DATABASE_NAME", "realdb"
      )
    end

    it "rewrites subtype-prefixed vars (POSTGRES_USER, etc.)" do
      app_service.environment_variables.create!(key: "POSTGRES_USER", value: "placeholder")
      app_service.environment_variables.create!(key: "POSTGRES_PASSWORD", value: "placeholder")
      app_service.environment_variables.create!(key: "POSTGRES_DB", value: "placeholder")
      app_service.environment_variables.create!(key: "DATABASE_URL", value: "postgres://placeholder:pass@host:5432/db")

      linker.rewrite_from_dsn(app_service, db_service)

      expect(engine).to have_received(:config_set).with(
        app_service.dokku_app_name, "POSTGRES_USER", "realuser"
      )
      expect(engine).to have_received(:config_set).with(
        app_service.dokku_app_name, "POSTGRES_PASSWORD", "realpass"
      )
      expect(engine).to have_received(:config_set).with(
        app_service.dokku_app_name, "POSTGRES_DB", "realdb"
      )
    end

    it "skips vars for unrelated subtypes" do
      app_service.environment_variables.create!(key: "MYSQL_USER", value: "placeholder")
      app_service.environment_variables.create!(key: "MYSQL_PASSWORD", value: "placeholder")
      app_service.environment_variables.create!(key: "DATABASE_URL", value: "postgres://placeholder:pass@host:5432/db")

      linker.rewrite_from_dsn(app_service, db_service)

      expect(engine).not_to have_received(:config_set).with(
        app_service.dokku_app_name, "MYSQL_USER", anything
      )
    end

    it "rewrites DATABASE_URL from the DSN even when its old value matches the db_service name" do
      app_service.environment_variables.create!(key: "DATABASE_URL", value: db_service.name)

      linker.rewrite_from_dsn(app_service, db_service)

      ev = app_service.environment_variables.find_by(key: "DATABASE_URL")
      expect(ev.value).to eq("postgres://realuser:realpass@dokku-postgres-web:5432/realdb")
    end

    it "skips unknown subtypes gracefully" do
      unknown = create(:service, :database, project: project, name: "unknown", subtype: "clickhouse")

      result = linker.rewrite_from_dsn(app_service, unknown)

      expect(result[:success]).to be(true)
    end

    it "returns failure when _info fails" do
      allow(engine).to receive(:postgres_info).and_return(success: false, dsn: nil, error: "connection refused")

      result = linker.rewrite_from_dsn(app_service, db_service)

      expect(result[:success]).to be(false)
      expect(result[:error]).to eq("Unable to read postgres connection URL")
    end
  end

  # ── ensure_network_aliases ──────────────────────────────

  describe "#ensure_network_aliases" do
    it "connects both containers to the project network" do
      allow(host_engine).to receive(:dokku_container_name).with(db_service.dokku_app_name)
        .and_return("dokku-postgres-container")
      allow(host_engine).to receive(:dokku_container_name).with(app_service.dokku_app_name)
        .and_return("dokku-app-container")

      linker.ensure_network_aliases(app_service, db_service)

      expect(network_manager).to have_received(:ensure_network!).once
      expect(network_manager).to have_received(:connect_container_with_aliases).with(
        "dokku-postgres-container", [ "postgres" ], wait: false
      )
      expect(network_manager).to have_received(:connect_container_with_aliases).with(
        "dokku-app-container", [ "web" ], wait: false
      )
    end

    it "skips containers that are not running yet" do
      allow(host_engine).to receive(:dokku_container_name).and_return(nil)

      linker.ensure_network_aliases(app_service, db_service)

      expect(network_manager).not_to have_received(:connect_container_with_aliases)
    end

    it "handles exceptions gracefully" do
      allow(host_engine).to receive(:dokku_container_name).and_raise(StandardError.new("ssh timeout"))

      expect {
        linker.ensure_network_aliases(app_service, db_service)
      }.not_to raise_error
    end
  end

  # ── ensure_db_network_aliases ───────────────────────────

  describe "#ensure_db_network_aliases" do
    it "connects all linked database containers" do
      linked_dbs = [ db_service ]
      allow(host_engine).to receive(:dokku_container_name).with(db_service.dokku_app_name)
        .and_return("dokku-postgres-container")

      linker.ensure_db_network_aliases(linked_dbs)

      expect(network_manager).to have_received(:ensure_network!)
      expect(network_manager).to have_received(:connect_container_with_aliases).with(
        "dokku-postgres-container", [ "postgres" ], wait: false
      )
    end

    it "returns early when linked_dbs is empty" do
      linker.ensure_db_network_aliases([])

      expect(network_manager).not_to have_received(:ensure_network!)
    end

    it "skips containers that are not running" do
      allow(host_engine).to receive(:dokku_container_name).and_return(nil)

      linker.ensure_db_network_aliases([ db_service ])

      expect(network_manager).not_to have_received(:connect_container_with_aliases)
    end

    it "handles exceptions gracefully" do
      allow(host_engine).to receive(:dokku_container_name).and_raise(StandardError.new("ssh timeout"))

      expect {
        linker.ensure_db_network_aliases([ db_service ])
      }.not_to raise_error
    end
  end

  # ── constructor ─────────────────────────────────────────

  describe "#initialize" do
    it "creates a HostEngine when none is provided" do
      allow(HostEngine).to receive(:new).with(server).and_return(host_engine)

      instance = described_class.new(project, engine)

      expect(instance).to be_a(described_class)
      expect(HostEngine).to have_received(:new).with(server)
    end
  end
end
