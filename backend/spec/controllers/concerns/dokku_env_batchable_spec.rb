require 'rails_helper'

RSpec.describe DokkuEnvBatchable do
  let(:test_class) do
    Class.new do
      include DokkuEnvBatchable
      attr_reader :service, :engine

      def initialize(service, engine)
        @service = service
        @engine = engine
      end

      public :build_full_env_hash, :resolve_manifest_placeholders, :preserve_host_only_keys
    end
  end

  let(:project) { create(:project) }
  let(:service) { create(:service, project: project) }
  let(:engine) { instance_double(DokkuEngine) }
  let(:helper) { test_class.new(service, engine) }

  describe "#build_full_env_hash" do
    before do
      allow(engine).to receive(:config_export_json).and_return({ success: true, output: "{}" })
    end

    it "includes both internal and user env vars" do
      service.environment_variables.create!(key: "RAILS_ENV", value: "production")
      service.environment_variables.create!(key: "DATABASE_URL", value: "postgres://x/y", is_dokku_internal: true, source: "dokku-link")

      hash = helper.build_full_env_hash(service, engine)
      expect(hash["RAILS_ENV"]).to eq("production")
      expect(hash["DATABASE_URL"]).to eq("postgres://x/y")
    end

    it "preserves any host-only key not in the DB" do
      service.environment_variables.create!(key: "RAILS_ENV", value: "production")

      allow(engine).to receive(:config_export_json).and_return({
        success: true,
        output: JSON.generate(
          "DATABASE_URL" => "postgres://user:pass@dokku-postgres-x:5432/db",
          "REDIS_URL" => "redis://x:6379",
          "DOKKU_POSTGRES_FOO" => "bar"
        )
      })

      hash = helper.build_full_env_hash(service, engine)
      expect(hash["DATABASE_URL"]).to eq("postgres://user:pass@dokku-postgres-x:5432/db")
      expect(hash["REDIS_URL"]).to eq("redis://x:6379")
      expect(hash["DOKKU_POSTGRES_FOO"]).to eq("bar")
    end

    it "prefers the DB value over the host value" do
      service.environment_variables.create!(key: "DATABASE_URL", value: "postgres://from-db/x", is_dokku_internal: true)

      allow(engine).to receive(:config_export_json).and_return({
        success: true,
        output: JSON.generate("DATABASE_URL" => "postgres://from-host/x")
      })

      hash = helper.build_full_env_hash(service, engine)
      expect(hash["DATABASE_URL"]).to eq("postgres://from-db/x")
    end

    it "tolerates a failed config_show" do
      service.environment_variables.create!(key: "RAILS_ENV", value: "production")

      allow(engine).to receive(:config_export_json).and_return({ success: false, output: "ssh error" })

      hash = helper.build_full_env_hash(service, engine)
      expect(hash["RAILS_ENV"]).to eq("production")
      expect(hash).not_to have_key("DATABASE_URL")
    end

    describe "manifest placeholder resolution" do
      it "resolves ${{ shared.X }} against project.shared_vars" do
        project.update!(shared_vars: [ { "key" => "GLOBAL_API_KEY", "value" => "secret-123" } ])
        service.environment_variables.create!(key: "API_KEY", value: "${{ shared.GLOBAL_API_KEY }}")

        hash = helper.build_full_env_hash(service, engine)
        expect(hash["API_KEY"]).to eq("secret-123")

        expect(service.environment_variables.find_by(key: "API_KEY").reload.value).to eq("${{ shared.GLOBAL_API_KEY }}")
      end

      it "resolves ${{ shared.X }} when value uses the [SHARED:X] pre-parsed marker" do
        project.update!(shared_vars: [ { "key" => "DOMAIN", "value" => "example.com" } ])
        service.environment_variables.create!(key: "APP_HOST", value: "[SHARED:DOMAIN]")

        hash = helper.build_full_env_hash(service, engine)
        expect(hash["APP_HOST"]).to eq("example.com")
      end

      it "resolves ${{ linked.SERVICE.VAR }} against the linked service" do
        linked = create(:service, project: project, name: "tween-pay-postgres")
        linked.environment_variables.create!(key: "DB_PASSWORD", value: "from-linked-db")
        service.environment_variables.create!(key: "RAILS_DATABASE_PASSWORD", value: "${{ linked.tween-pay-postgres.DB_PASSWORD }}")
        service.outgoing_links.create!(to_service: linked)

        hash = helper.build_full_env_hash(service, engine)
        expect(hash["RAILS_DATABASE_PASSWORD"]).to eq("from-linked-db")
      end

      it "excludes unresolvable placeholders from the hash to avoid writing markers to Dokku" do
        service.environment_variables.create!(key: "API_KEY", value: "${{ shared.NONEXISTENT }}")

        hash = helper.build_full_env_hash(service, engine)
        expect(hash).not_to have_key("API_KEY")
      end

      it "excludes unresolved LINKED markers from the hash" do
        service.environment_variables.create!(key: "DB_PORT", value: "[LINKED:my-postgres:PORT]")

        hash = helper.build_full_env_hash(service, engine)
        expect(hash).not_to have_key("DB_PORT")
      end

      it "excludes unresolved SHARED markers from the hash" do
        service.environment_variables.create!(key: "SECRET", value: "[SHARED:MISSING_KEY]")

        hash = helper.build_full_env_hash(service, engine)
        expect(hash).not_to have_key("SECRET")
      end

      it "does not touch plain values without placeholders" do
        service.environment_variables.create!(key: "RAILS_ENV", value: "production")

        hash = helper.build_full_env_hash(service, engine)
        expect(hash["RAILS_ENV"]).to eq("production")
      end

      it "resolves placeholders embedded inside larger strings" do
        project.update!(shared_vars: [ { "key" => "DOMAIN", "value" => "tween.im" } ])
        service.environment_variables.create!(key: "CORS", value: "https://${{ shared.DOMAIN }},https://api.${{ shared.DOMAIN }}")

        hash = helper.build_full_env_hash(service, engine)
        expect(hash["CORS"]).to eq("https://tween.im,https://api.tween.im")
      end
    end
  end
end
