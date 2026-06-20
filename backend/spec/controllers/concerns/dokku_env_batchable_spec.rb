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

      public :build_full_env_hash, :preserve_host_only_keys
    end
  end

  let(:project) { create(:project) }
  let(:service) { create(:service, project: project) }
  let(:engine) { instance_double(DokkuEngine) }
  let(:helper) { test_class.new(service, engine) }

  describe "#build_full_env_hash" do
    it "includes both internal and user env vars" do
      service.environment_variables.create!(key: "RAILS_ENV", value: "production")
      service.environment_variables.create!(key: "DATABASE_URL", value: "postgres://x/y", is_dokku_internal: true, source: "dokku-link")

      allow(engine).to receive(:config_show).and_return({ success: true, output: "" })

      hash = helper.build_full_env_hash(service, engine)
      expect(hash["RAILS_ENV"]).to eq("production")
      expect(hash["DATABASE_URL"]).to eq("postgres://x/y")
    end

    it "preserves any host-only key not in the DB" do
      service.environment_variables.create!(key: "RAILS_ENV", value: "production")

      allow(engine).to receive(:config_show).and_return({
        success: true,
        output: <<~ENV
          DATABASE_URL=postgres://user:pass@dokku-postgres-x:5432/db
          REDIS_URL=redis://x:6379
          DOKKU_POSTGRES_FOO=bar
        ENV
      })

      hash = helper.build_full_env_hash(service, engine)
      expect(hash["DATABASE_URL"]).to eq("postgres://user:pass@dokku-postgres-x:5432/db")
      expect(hash["REDIS_URL"]).to eq("redis://x:6379")
      expect(hash["DOKKU_POSTGRES_FOO"]).to eq("bar")
    end

    it "skips placeholder values like ${{ shared.FOO }}" do
      service.environment_variables.create!(key: "RAILS_ENV", value: "production")

      allow(engine).to receive(:config_show).and_return({
        success: true,
        output: "DATABASE_URL=${{ shared.DATABASE_URL }}\n"
      })

      hash = helper.build_full_env_hash(service, engine)
      expect(hash).not_to have_key("DATABASE_URL")
    end

    it "prefers the DB value over the host value" do
      service.environment_variables.create!(key: "DATABASE_URL", value: "postgres://from-db/x", is_dokku_internal: true)

      allow(engine).to receive(:config_show).and_return({
        success: true,
        output: "DATABASE_URL=postgres://from-host/x\n"
      })

      hash = helper.build_full_env_hash(service, engine)
      expect(hash["DATABASE_URL"]).to eq("postgres://from-db/x")
    end

    it "does not duplicate keys that exist in both DB and host" do
      service.environment_variables.create!(key: "RAILS_ENV", value: "production")

      allow(engine).to receive(:config_show).and_return({
        success: true,
        output: "RAILS_ENV=production\nEXTRA_KEY=extra-value\n"
      })

      hash = helper.build_full_env_hash(service, engine)
      expect(hash["RAILS_ENV"]).to eq("production")
      expect(hash["EXTRA_KEY"]).to eq("extra-value")
      expect(hash.size).to eq(2)
    end

    it "tolerates a failed config_show" do
      service.environment_variables.create!(key: "RAILS_ENV", value: "production")

      allow(engine).to receive(:config_show).and_return({ success: false, output: "ssh error" })

      hash = helper.build_full_env_hash(service, engine)
      expect(hash["RAILS_ENV"]).to eq("production")
      expect(hash).not_to have_key("DATABASE_URL")
    end
  end
end
