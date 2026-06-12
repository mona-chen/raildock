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
        expect(svc[:proxy][:ports]).to eq([ { host: 80, container: 3000, scheme: "http" } ])
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

  describe 'placeholder resolution (resolve_placeholders)' do
    def resolve(value)
      described_class.send(:new).send(:resolve_placeholders, value)
    end

    describe 'Coolify-style legacy placeholders' do
      it 'resolves $SERVICE_PASSWORD_XXX to random hex' do
        result = resolve('$SERVICE_PASSWORD_MYSECRET')
        expect(result).to match(/\h{32}/)
      end

      it 'resolves $SERVICE_PASSWORD_64_XXX to random hex' do
        result = resolve('$SERVICE_PASSWORD_64_APIKEY')
        expect(result).to match(/\h{32}/)
      end

      it 'resolves $SERVICE_USER_XXX to "user"' do
        result = resolve('$SERVICE_USER_POSTGRESQL')
        expect(result).to eq("user")
      end

      it 'resolves $SERVICE_URL_XXX to a public-domain marker' do
        result = resolve('$SERVICE_URL_REDIS')
        expect(result).to eq("https://[RAILDOCK_PUBLIC_DOMAIN]")
      end

      it 'resolves $SERVICE_FQDN_XXX to a public-domain marker' do
        result = resolve('$SERVICE_FQDN_MYAPP')
        expect(result).to eq("[RAILDOCK_PUBLIC_DOMAIN]")
      end

      it 'resolves $SERVICE_BASE64_XXX to base64 string' do
        result = resolve('$SERVICE_BASE64_SECRET')
        expect(result).not_to include('$')
      end

      it 'resolves bare $SERVICE_PASSWORD' do
        result = resolve('$SERVICE_PASSWORD')
        expect(result).to match(/\h{32}/)
      end

      it 'resolves bare $SERVICE_USER' do
        result = resolve('$SERVICE_USER')
        expect(result).to eq("user")
      end

      it 'resolves CHANGE_ME to random hex' do
        result = resolve('CHANGE_ME')
        expect(result).to match(/\h{32}/)
      end

      it 'resolves CHANGE_ME embedded in a URL' do
        result = resolve('postgres://user:CHANGE_ME@localhost/db')
        expect(result).to match(/postgres:\/\/user:\h{32}@localhost\/db/)
      end
    end

    describe 'Railway-style ${{ }} expressions' do
      it 'resolves ${{ secret() }} to 32-char hex' do
        result = resolve('${{ secret() }}')
        expect(result).to match(/\h{32}/)
      end

      it 'resolves ${{ secret(N) }} to N-char hex' do
        result = resolve('${{ secret(16) }}')
        expect(result).to match(/\h{16}/)
      end

      it 'caps secret length at 128' do
        result = resolve('${{ secret(200) }}')
        expect(result.length).to eq(128)
      end

      it 'resolves ${{ randomInt(1, 100) }} to integer string' do
        result = resolve('${{ randomInt(1, 100) }}')
        expect(result.to_i).to be_between(1, 100)
      end

      it 'handles ${{ randomInt(50, 50) }} (same min/max)' do
        result = resolve('${{ randomInt(42, 42) }}')
        expect(result).to eq("42")
      end

      it 'swaps min/max if reversed' do
        result = resolve('${{ randomInt(100, 1) }}')
        expect(result.to_i).to be_between(1, 100)
      end

      it 'resolves ${{ RAILDOCK_PUBLIC_DOMAIN }} to marker tag' do
        result = resolve('${{ RAILDOCK_PUBLIC_DOMAIN }}')
        expect(result).to eq("[RAILDOCK_PUBLIC_DOMAIN]")
      end

      it 'resolves ${{ shared.VAR }} to marker tag' do
        result = resolve('${{ shared.API_KEY }}')
        expect(result).to eq("[SHARED:API_KEY]")
      end

    it 'resolves ${{ linked.SERVICE.VAR }} to marker tag' do
      result = resolve('${{ linked.postgres.DATABASE_URL }}')
      expect(result).to eq("[LINKED:postgres:DATABASE_URL]")
    end

    it 'allows hyphens in linked service names' do
      result = resolve('${{ linked.coder-database.DATABASE_URL }}')
      expect(result).to eq("[LINKED:coder-database:DATABASE_URL]")
    end
    end

    describe 'mixed content' do
      it 'resolves mixed legacy and Railway-style' do
        result = resolve('https://${{ RAILDOCK_PUBLIC_DOMAIN }}/api?key=$SERVICE_PASSWORD_MYKEY')
        expect(result).to eq("https://[RAILDOCK_PUBLIC_DOMAIN]/api?key=#{/\h{32}/.match(result)[0]}")
      end

      it 'leaves plain strings unchanged' do
        result = resolve('https://example.com')
        expect(result).to eq('https://example.com')
      end
    end
  end

  describe '.resolve_runtime' do
    def resolve_runtime(env_value, project: nil, service: nil, linked_services: [])
      described_class.resolve_runtime(env_value, project, service, linked_services)
    end

    it 'resolves [RAILDOCK_PUBLIC_DOMAIN] to service domain' do
      domain = double(:domain, hostname: 'myapp.up.railway.app')
      service = double(:service, domains: [ domain ])
      result = resolve_runtime('[RAILDOCK_PUBLIC_DOMAIN]', service:)
      expect(result).to eq('myapp.up.railway.app')
    end

    it 'leaves [RAILDOCK_PUBLIC_DOMAIN] unresolved when no service domain' do
      service = double(:service, domains: [])
      result = resolve_runtime('[RAILDOCK_PUBLIC_DOMAIN]', service:)
      expect(result).to eq('[RAILDOCK_PUBLIC_DOMAIN]')
    end

    it 'resolves [LINKED:svc:VAR] to linked service env var' do
      linked_svc = double(:service, name: 'postgres')
      ev = double(:ev, key: 'DATABASE_URL', value: 'postgres://user:pass@host/db')
      allow(linked_svc).to receive(:environment_variables).and_return([ ev ])
      result = resolve_runtime('[LINKED:postgres:DATABASE_URL]', linked_services: [ linked_svc ])
      expect(result).to eq('postgres://user:pass@host/db')
    end

    it 'returns marker unchanged when linked service not found' do
      result = resolve_runtime('[LINKED:redis:REDIS_URL]', linked_services: [])
      expect(result).to eq('[LINKED:redis:REDIS_URL]')
    end

    it 'returns marker unchanged when variable not found on linked service' do
      linked_svc = double(:service, name: 'postgres', environment_variables: [])
      result = resolve_runtime('[LINKED:postgres:MISSING_VAR]', linked_services: [ linked_svc ])
      expect(result).to eq('[LINKED:postgres:MISSING_VAR]')
    end

    it 'leaves plain values without markers unchanged' do
      result = resolve_runtime('postgres://user:pass@localhost/db')
      expect(result).to eq('postgres://user:pass@localhost/db')
    end

    it 'resolves multiple markers in one value' do
      svc_domain = double(:domain, hostname: 'app.example.com')
      app_service = double(:service, domains: [ svc_domain ])
      linked_svc = double(:service, name: 'postgres')
      ev = double(:ev, key: 'DATABASE_URL', value: 'postgres://user:pass@host/db')
      allow(linked_svc).to receive(:environment_variables).and_return([ ev ])

      # Use pre-parsed markers (normal flow after ManifestParser.parse)
      result = resolve_runtime(
        'postgres://[LINKED:postgres:DATABASE_URL]@[RAILDOCK_PUBLIC_DOMAIN]',
        service: app_service,
        linked_services: [ linked_svc ]
      )
      expect(result).to eq('postgres://postgres://user:pass@host/db@app.example.com')
    end
  end

  describe 'integration: parse + resolve_runtime' do
    it 'parses template with ${{ }} vars and resolves markers after deploy' do
      toml = <<~TOML
        name = "Coder"

        [[services]]
        name = "coder"
        category = "app"
        subtype = "docker"
        docker_image = "ghcr.io/coder/coder:latest"
        source = { type = "docker" }

          [services.env]
          CODER_PG_CONNECTION_URL = "${{ linked.coder-database.DATABASE_URL }}"
          CODER_ACCESS_URL = "https://${{ RAILDOCK_PUBLIC_DOMAIN }}"

        [[services]]
        name = "coder-database"
        category = "database"
        subtype = "postgres"
        docker_image = "postgres:16.4-alpine"
        source = { type = "docker" }

          [services.env]
          POSTGRES_PASSWORD = "${{ secret() }}"

        [[links]]
        from = "coder"
        to = "coder-database"
      TOML

      result = described_class.parse(toml, filename: "raildock.toml")

      coder_svc = result.find_service("coder")
      expect(coder_svc[:env]["CODER_PG_CONNECTION_URL"]).to eq("[LINKED:coder-database:DATABASE_URL]")
      expect(coder_svc[:env]["CODER_ACCESS_URL"]).to eq("https://[RAILDOCK_PUBLIC_DOMAIN]")

      db_svc = result.find_service("coder-database")
      expect(db_svc[:env]["POSTGRES_PASSWORD"]).to match(/\h{32}/)
    end
  end
end
