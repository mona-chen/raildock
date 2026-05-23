require 'rails_helper'

RSpec.describe ManifestGenerator do
  let(:project) { create(:project, name: "Test Project") }

  describe '#generate' do
    context 'with an empty project' do
      it 'returns a minimal manifest' do
        generator = described_class.new(project)
        result = generator.generate(format: :toml)

        expect(result).to include("# RailDock Manifest for Test Project")
        expect(result).to include("# Generated from project state")
      end
    end

    context 'with services' do
      before do
        @web = project.services.create!(
          name: "web",
          service_type: "app",
          subtype: "rails",
          status: "stopped",
          builder: "nixpacks",
          git_repo: "https://github.com/test/app",
          branch: "main",
          config: {
            "proxy" => { "enabled" => true, "proxyType" => "traefik", "portMappings" => [{ "hostPort" => 80, "containerPort" => 3000, "scheme" => "http" }] },
            "checks" => { "enabled" => true, "wait" => 5, "timeout" => 30, "skipList" => [] },
            "letsencrypt" => { "enabled" => true, "email" => "admin@example.com" }
          }
        )
        @web.process_types.create!(name: "web", quantity: 2, running: 2, command: "")
        @web.environment_variables.create!(key: "RAILS_ENV", value: "production")
        @web.domains.create!(hostname: "api.example.com", port: 443, ssl: true)
        @web.storage_mounts.create!(host_path: "/data/uploads", container_path: "/app/public/uploads")

        @db = project.services.create!(
          name: "database",
          service_type: "database",
          subtype: "postgres",
          status: "running",
          version: "16"
        )

        ServiceLink.create!(from_service: @web, to_service: @db)
      end

      it 'generates TOML with all services' do
        generator = described_class.new(project)
        toml = generator.generate(format: :toml)

        expect(toml).to include('name = "web"')
        expect(toml).to include('category = "app"')
        expect(toml).to include('subtype = "rails"')
        expect(toml).to include('builder = "nixpacks"')
        expect(toml).to include('repo = "https://github.com/test/app"')
        expect(toml).to include('branch = "main"')
        expect(toml).to include('RAILS_ENV = "production"')
        expect(toml).to include('api.example.com')
        expect(toml).to include('host = "/data/uploads"')
        expect(toml).to include('container = "/app/public/uploads"')
        expect(toml).to include('web = 2')
        expect(toml).to include('enabled = true')
        expect(toml).to include('type = "traefik"')
        expect(toml).to include('name = "database"')
        expect(toml).to include('category = "database"')
        expect(toml).to include('version = "16"')
        expect(toml).to include('from = "web"')
        expect(toml).to include('to = "database"')
      end

      it 'generates valid JSON' do
        generator = described_class.new(project)
        json = generator.generate(format: :json)
        parsed = JSON.parse(json)

        expect(parsed["services"].length).to eq(2)
        expect(parsed["links"].length).to eq(1)
      end

      it 'round-trips through ManifestParser' do
        generator = described_class.new(project)
        toml = generator.generate(format: :toml)

        parsed = ManifestParser.parse(toml, filename: "raildock.toml")
        expect(parsed.services.length).to eq(2)

        web = parsed.find_service("web")
        expect(web[:category]).to eq("app")
        expect(web[:subtype]).to eq("rails")
        expect(web[:env]["RAILS_ENV"]).to eq("production")
        expect(web[:scaling]["web"]).to eq(2)
        expect(web[:domains]).to include("api.example.com")
        expect(web[:proxy][:type]).to eq("traefik")
      end
    end
  end
end
