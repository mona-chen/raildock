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

      it 'maps [services.resources] to per-process limits' do
        toml_with_resources = <<~TOML
          name = "Resourced"

          [[services]]
          name = "web"
          category = "app"
          subtype = "rails"
          builder = "nixpacks"
          source = { type = "git", repo = "https://github.com/test/app", branch = "main" }

            [services.resources]
            memory = "512m"
            cpus = "0.5"
        TOML

        result = described_class.parse(toml_with_resources, filename: "raildock.toml")
        web = result.find_service("web")

        expect(web[:limits]).to eq({ "web" => { memory: "512m", cpu: "0.5" } })
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

      it "uses the standard repository field as the deploy source" do
        result = described_class.parse(
          {
            name: "example",
            repository: "https://github.com/acme/example",
            env: {}
          }.to_json,
          filename: "app.json"
        )

        expect(result.services.first.dig(:source, :repo)).to eq("https://github.com/acme/example")
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

    it "does not invent proxy configuration when the block is omitted" do
      result = described_class.parse(
        <<~TOML,
          [[services]]
          name = "postgres"
          category = "database"
          subtype = "postgres"
        TOML
        filename: "raildock.toml"
      )

      expect(result.find_service("postgres")[:proxy]).to eq({})
    end

    context 'with railway.toml' do
      let(:toml) do
        <<~TOML
          [build]
          builder = "railpack"
          buildCommand = "echo building!"

          [deploy]
          startCommand = "npm start"
          healthcheckPath = "/healthz"
          healthcheckTimeout = 30
          restartPolicyType = "ON_FAILURE"

          [vars]
          NODE_ENV = "production"
        TOML
      end

      it 'parses into single service with Railway fields mapped' do
        result = described_class.parse(toml, filename: "railway.toml")

        expect(result.format_detected).to eq("railway.toml")
        expect(result.services.length).to eq(1)

        svc = result.services.first
        expect(svc[:name]).to eq("app")
        expect(svc[:builder]).to eq("railpack")
        expect(svc[:start_command]).to eq("npm start")
        expect(svc[:checks][:enabled]).to be(true)
        expect(svc[:checks][:path]).to eq("/healthz")
        expect(svc[:checks][:timeout]).to eq(30)
        expect(svc[:restart_policy]).to eq("on-failure")
        expect(svc[:env]).to eq({ "NODE_ENV" => "production" })
      end

      it 'records buildCommand for lifecycle visibility' do
        result = described_class.parse(toml, filename: "railway.toml")
        expect(result.services.first.dig(:scripts, :build)).to eq("echo building!")
      end

      it 'warns that single-service config cannot do links or storage' do
        result = described_class.parse(toml, filename: "railway.toml")
        expect(result.warnings).to include(a_string_matching(/does not support domains/))
        expect(result.warnings).to include(a_string_matching(/does not support service links/))
      end
    end

    context 'with railway.json' do
      let(:json) do
        <<~JSON
          {
            "build": { "builder": "nixpacks" },
            "deploy": {
              "startCommand": ["npm", "run", "start"],
              "healthcheckPath": "/",
              "restartPolicyType": "ALWAYS"
            },
            "env": {
              "API_KEY": "${{ secrets.API_KEY }}",
              "PORT": { "value": "3000" }
            },
            "vars": { "NODE_ENV": "production" }
          }
        JSON
      end

      it 'parses TOML and JSON identically' do
        result = described_class.parse(json, filename: "railway.json")
        expect(result.format_detected).to eq("railway.json")
        svc = result.services.first
        expect(svc[:builder]).to eq("nixpacks")
        expect(svc[:start_command]).to eq("npm && run && start")
        expect(svc[:checks][:path]).to eq("/")
        expect(svc[:restart_policy]).to eq("always")
      end

      it 'joins array startCommand with " && "' do
        result = described_class.parse(json, filename: "railway.json")
        expect(result.services.first[:start_command]).to eq("npm && run && start")
      end

      it 'merges [env] and [vars] with [vars] winning on conflict' do
        json_with_conflict = <<~JSON
          {
            "deploy": { "startCommand": "node index.js" },
            "env": { "SHARED": "from-env" },
            "vars": { "SHARED": "from-vars" }
          }
        JSON
        result = described_class.parse(json_with_conflict, filename: "railway.json")
        expect(result.services.first[:env]).to eq({ "SHARED" => "from-vars" })
      end

      it 'leaves Railway-only markers like ${{ secrets.X }} as opaque strings' do
        result = described_class.parse(json, filename: "railway.json")
        expect(result.services.first[:env]["API_KEY"]).to eq("${{ secrets.API_KEY }}")
      end

      it 'resolves generator hash values to GENERATED markers' do
        json_with_gen = <<~JSON
          {
            "deploy": { "startCommand": "node index.js" },
            "vars": { "DB_PASS": { "generator": "secret" } }
          }
        JSON
        result = described_class.parse(json_with_gen, filename: "railway.json")
        expect(result.services.first[:env]["DB_PASS"]).to eq("SECRET_GENERATED")
      end
    end

    context 'with unknown Railway builder' do
      it 'still produces a service hash with builder=nil and a warning' do
        json = <<~JSON
          {
            "build": { "builder": "Bazel" },
            "deploy": { "startCommand": "make run" }
          }
        JSON
        result = described_class.parse(json, filename: "railway.json")
        expect(result.services.first[:builder]).to be_nil
        expect(result.warnings).to include(a_string_matching(/builder 'Bazel' is not in RailDock's enum/))
      end

      it 'normalizes DOCKERFILE to dockerfile without warning' do
        json = <<~JSON
          {
            "build": { "builder": "DOCKERFILE" },
            "deploy": { "startCommand": "echo hi" }
          }
        JSON
        result = described_class.parse(json, filename: "railway.json")
        expect(result.services.first[:builder]).to eq("dockerfile")
        expect(result.warnings).not_to include(a_string_matching(/is not in RailDock's enum/))
      end
    end

    context 'with preDeployCommand' do
      it 'records preDeployCommand for lifecycle visibility' do
        json = <<~JSON
          {
            "deploy": {
              "startCommand": "node index.js",
              "preDeployCommand": ["npm", "run", "migrate"]
            }
          }
        JSON
        result = described_class.parse(json, filename: "railway.json")
        expect(result.services.first.dig(:scripts, :predeploy)).to eq("npm && run && migrate")
      end
    end

    context 'with no filename hint (auto-detection)' do
      it 'detects railway.toml from [build] section' do
        toml = "[build]\nbuilder = \"railpack\"\n[deploy]\nstartCommand = \"echo hi\"\n"
        result = described_class.parse(toml)
        expect(result.format_detected).to eq("railway.toml")
      end

      it 'detects railway.json from "build" top-level key' do
        json = '{ "build": { "builder": "railpack" }, "deploy": { "startCommand": "echo hi" } }'
        result = described_class.parse(json)
        expect(result.format_detected).to eq("railway.json")
      end

      it 'detects railway.json from "deploy" top-level key' do
        json = '{ "deploy": { "startCommand": "echo hi" } }'
        result = described_class.parse(json)
        expect(result.format_detected).to eq("railway.json")
      end

      it 'does not misroute a railway.json as app.json or raildock.json' do
        json = '{ "build": { "builder": "railpack" }, "deploy": { "startCommand": "echo hi" } }'
        result = described_class.parse(json)
        expect(result.format_detected).not_to eq("app.json")
        expect(result.format_detected).not_to eq("raildock.json")
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

    it 'resolves ${{ env.VAR }} to marker tag' do
      result = resolve('${{ env.SECRET_KEY_BASE }}')
      expect(result).to eq("[ENV:SECRET_KEY_BASE]")
    end

    it "resolves shared markers from the project's shared variable objects" do
      project = build(:project, shared_vars: [ { key: "API_KEY", value: "secret" } ])

      result = described_class.resolve_runtime("[SHARED:API_KEY]", project, nil, [])

      expect(result).to eq("secret")
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

    it "resolves [ENV:VAR] to the service's own stored value" do
      ev = double(:ev, key: 'SECRET_KEY_BASE', value: 'stored-secret')
      service = double(:service, name: 'web', environment_variables: [ ev ])
      result = resolve_runtime('[ENV:SECRET_KEY_BASE]', service:)
      expect(result).to eq('stored-secret')
    end

    it 'resolves raw ${{ env.VAR }} syntax too' do
      ev = double(:ev, key: 'SECRET_KEY_BASE', value: 'stored-secret')
      service = double(:service, name: 'web', environment_variables: [ ev ])
      result = resolve_runtime('${{ env.SECRET_KEY_BASE }}', service:)
      expect(result).to eq('stored-secret')
    end

    it 'leaves [ENV:VAR] marker when nothing is stored for the key' do
      service = double(:service, name: 'web', environment_variables: [])
      result = resolve_runtime('[ENV:MISSING]', service:)
      expect(result).to eq('[ENV:MISSING]')
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

  describe 'raw secret warnings' do
    def parse_env_warnings(env_lines)
      toml = <<~TOML
        [[services]]
        name = "web"
        category = "app"

          [services.env]
          #{env_lines}
      TOML
      described_class.parse(toml, filename: "raildock.toml").warnings
    end

    it 'warns when a secret-looking value is written raw' do
      warnings = parse_env_warnings('SECRET_KEY_BASE = "a1b2c3deadbeef"')
      expect(warnings.length).to eq(1)
      expect(warnings.first).to include("SECRET_KEY_BASE")
      expect(warnings.first).to include("${{ env.SECRET_KEY_BASE }}")
    end

    it 'does not warn for reference syntax' do
      warnings = parse_env_warnings('SECRET_KEY_BASE = "${{ shared.SECRET_KEY_BASE }}"')
      expect(warnings).to be_empty
    end

    it 'does not warn for non-secret keys' do
      warnings = parse_env_warnings('RAILS_ENV = "production"')
      expect(warnings).to be_empty
    end

    it 'parses ${{ env.VAR }} values into [ENV:VAR] markers' do
      toml = <<~TOML
        [[services]]
        name = "web"
        category = "app"

          [services.env]
          SECRET_KEY_BASE = "${{ env.SECRET_KEY_BASE }}"
      TOML
      result = described_class.parse(toml, filename: "raildock.toml")
      web = result.find_service("web")
      expect(web[:env]["SECRET_KEY_BASE"]).to eq("[ENV:SECRET_KEY_BASE]")
      expect(result.warnings).to be_empty
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
