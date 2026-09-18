require "rails_helper"

RSpec.describe StaticSiteConfigurator do
  def service_with(config:, builder: "nixpacks", start_command: nil, docker_image: nil)
    build(
      :service,
      builder: builder,
      start_command: start_command,
      docker_image: docker_image,
      config: config
    )
  end

  let(:static_config) { { "staticSite" => { "publishDirectory" => "dist" } } }

  describe "#static?" do
    it "is true for an app with a publish directory" do
      expect(described_class.new(service_with(config: static_config))).to be_static
    end

    it "is false without a publish directory" do
      expect(described_class.new(service_with(config: {}))).not_to be_static
    end

    it "is false when an explicit start_command is set" do
      configurator = described_class.new(service_with(config: static_config, start_command: "node server.js"))
      expect(configurator).not_to be_static
    end

    it "is false for docker-image services" do
      configurator = described_class.new(service_with(config: static_config, docker_image: "nginx"))
      expect(configurator).not_to be_static
    end

    it "is true even when the configured builder cannot serve static builds" do
      configurator = described_class.new(service_with(config: static_config, builder: "herokuish"))
      expect(configurator).to be_static
    end
  end

  describe "#resolve_builder" do
    let(:all_available) { ->(_slug) { true } }
    let(:only_nixpacks) { ->(slug) { slug == "nixpacks" } }

    it "prefers railpack when available" do
      configurator = described_class.new(service_with(config: static_config, builder: "auto"))
      expect(configurator.resolve_builder(available: all_available)).to eq("railpack")
    end

    it "falls back to nixpacks when railpack is unavailable" do
      configurator = described_class.new(service_with(config: static_config, builder: "auto"))
      expect(configurator.resolve_builder(available: only_nixpacks)).to eq("nixpacks")
    end

    it "overrides a builder that cannot serve static sites" do
      configurator = described_class.new(service_with(config: static_config, builder: "herokuish"))
      expect(configurator.resolve_builder(available: all_available)).to eq("railpack")
      expect(configurator.builder_overridden?("railpack")).to be(true)
    end

    it "leaves a Dockerfile deploy alone" do
      configurator = described_class.new(service_with(config: static_config, builder: "dockerfile"))
      expect(configurator.resolve_builder(available: all_available)).to be_nil
    end

    it "does not touch the builder for non-static services" do
      configurator = described_class.new(service_with(config: {}, builder: "herokuish"))
      expect(configurator.resolve_builder(available: all_available)).to be_nil
    end

    it "returns nil when no static builder is installed" do
      configurator = described_class.new(service_with(config: static_config, builder: "auto"))
      expect(configurator.resolve_builder(available: ->(_slug) { false })).to be_nil
    end
  end

  describe "#passthrough?" do
    it "is true for a Dockerfile deploy" do
      configurator = described_class.new(service_with(config: static_config, builder: "dockerfile"))
      expect(configurator).to be_passthrough
    end

    it "is false when RailDock picks a built-in builder" do
      configurator = described_class.new(service_with(config: static_config, builder: "auto"))
      expect(configurator).not_to be_passthrough
    end

    it "is false for non-static services" do
      configurator = described_class.new(service_with(config: {}, builder: "dockerfile"))
      expect(configurator).not_to be_passthrough
    end
  end

  describe "#build_env" do
    it "sets the railpack publish directory" do
      configurator = described_class.new(service_with(config: static_config))
      expect(configurator.build_env("railpack")).to eq("RAILPACK_SPA_OUTPUT_DIR" => "dist")
    end

    it "pins a supported Node version for nixpacks" do
      configurator = described_class.new(service_with(config: static_config))
      expect(configurator.build_env("nixpacks")).to eq(
        "NIXPACKS_SPA_OUT_DIR" => "dist",
        "NIXPACKS_NODE_VERSION" => "22"
      )
    end

    it "honours a configured Node version" do
      config = { "staticSite" => { "publishDirectory" => "dist", "nodeVersion" => "20" } }
      configurator = described_class.new(service_with(config: config))

      expect(configurator.build_env("nixpacks")["NIXPACKS_NODE_VERSION"]).to eq("20")
      expect(configurator.build_env("railpack")["RAILPACK_NODE_VERSION"]).to eq("20")
    end

    it "returns nothing for builders that are not static-capable" do
      configurator = described_class.new(service_with(config: static_config))
      expect(configurator.build_env("herokuish")).to eq({})
    end
  end

  describe "#serve_command" do
    it "uses the railpack Caddyfile path" do
      configurator = described_class.new(service_with(config: static_config))
      expect(configurator.serve_command("railpack")).to eq("caddy run --config /Caddyfile --adapter caddyfile")
    end

    it "uses the nixpacks assets path" do
      configurator = described_class.new(service_with(config: static_config))
      expect(configurator.serve_command("nixpacks")).to eq("caddy run --config /assets/Caddyfile --adapter caddyfile")
    end

    it "returns nil when not static" do
      configurator = described_class.new(service_with(config: {}))
      expect(configurator.serve_command("railpack")).to be_nil
    end
  end
end
