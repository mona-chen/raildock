require 'rails_helper'

RSpec.describe ManifestParser do
  describe '.parse' do
    context 'with raildock.toml' do
      let(:toml) do
        <<~TOML
          name = "Test Stack"

          [[services]]
          name = "web"
          category = "app"
          subtype = "rails"
          builder = "nixpacks"
          source = { type = "git", repo = "https://github.com/test/app", branch = "main" }

            [services.scaling]
            web = 2

            [services.env]
            RAILS_ENV = "production"

          [[services]]
          name = "database"
          category = "database"
          subtype = "postgres"
          version = "16"

          [[links]]
          from = "web"
          to = "database"
        TOML
      end

      it 'parses services and links' do
        result = described_class.parse(toml, filename: "raildock.toml")

        expect(result.format_detected).to eq("raildock.toml")
        expect(result.services.length).to eq(2)
        expect(result.links.length).to eq(1)

        web = result.find_service("web")
        expect(web[:category]).to eq("app")
        expect(web[:subtype]).to eq("rails")
        expect(web[:builder]).to eq("nixpacks")
        expect(web[:source]).to eq({ type: "git", repo: "https://github.com/test/app", branch: "main" })
        expect(web[:scaling]).to eq({ "web" => 2 })
        expect(web[:env]).to eq({ "RAILS_ENV" => "production" })

        db = result.find_service("database")
        expect(db[:category]).to eq("database")
        expect(db[:subtype]).to eq("postgres")
        expect(db[:version]).to eq("16")

        link = result.links.first
        expect(link[:from]).to eq("web")
        expect(link[:to]).to eq("database")
      end
    end

    context 'with app.json' do
      let(:json) do
        <<~JSON
          {
            "name": "my-app",
            "buildpacks": ["heroku/ruby"],
            "env": {
              "RAILS_ENV": "production",
              "SECRET": { "generator": "secret" }
            },
            "formation": {
              "web": { "quantity": 2 },
              "worker": { "quantity": 1 }
            },
            "cron": [
              { "command": "rake cleanup", "schedule": "0 2 * * *" }
            ]
          }
        JSON
      end

      it 'parses into single service' do
        result = described_class.parse(json, filename: "app.json")

        expect(result.format_detected).to eq("app.json")
        expect(result.services.length).to eq(1)
        expect(result.warnings).to include(a_string_matching(/app.json does not support domains/))

        svc = result.services.first
        expect(svc[:name]).to eq("my-app")
        expect(svc[:subtype]).to eq("rails")
        expect(svc[:scaling]).to eq({ "web" => 2, "worker" => 1 })
        expect(svc[:env]).to eq({ "RAILS_ENV" => "production", "SECRET" => "SECRET_GENERATED" })
        expect(svc[:cron].length).to eq(1)
      end
    end

    context 'with raildock.json' do
      let(:json) do
        <<~JSON
          {
            "services": [
              {
                "name": "api",
                "category": "app",
                "subtype": "node",
                "proxy": {
                  "enabled": true,
                  "type": "traefik",
                  "ports": [{ "host": 80, "container": 3000 }]
                }
              }
            ]
          }
        JSON
      end

      it 'parses proxy config' do
        result = described_class.parse(json, filename: "raildock.json")

        expect(result.format_detected).to eq("raildock.json")
        svc = result.find_service("api")
        expect(svc[:proxy][:type]).to eq("traefik")
        expect(svc[:proxy][:ports]).to eq([{ host: 80, container: 3000, scheme: "http" }])
      end
    end

    context 'with invalid format' do
      it 'raises ParseError' do
        expect {
          described_class.parse("not a valid format")
        }.to raise_error(ManifestParser::ParseError)
      end
    end
  end
end
