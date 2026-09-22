require "rails_helper"
require "ostruct"

RSpec.describe RepositoryDiscovery do
  let(:repository) { "acme/storefront" }
  let(:commit_sha) { "a" * 40 }
  let(:git_source) do
    instance_double(
      GitSource,
      installation_id: 123,
      github_app?: true,
      repos: [ { "full_name" => repository, "default_branch" => "main" } ]
    )
  end
  let(:client) { double("Octokit client") }

  before do
    allow(client).to receive(:branch).with(repository, "main").and_return(
      OpenStruct.new(commit: OpenStruct.new(sha: commit_sha))
    )
  end

  it "honors a Railway Dockerfile decision without asking the user for a builder" do
    stub_tree("railway.toml", "Dockerfile", "Gemfile")
    stub_content("railway.toml", <<~TOML)
      [build]
      builder = "DOCKERFILE"
      dockerfilePath = "docker/production.Dockerfile"

      [deploy]
      healthcheckPath = "/health"
      restartPolicyType = "ON_FAILURE"
    TOML

    result = described_class.new(git_source: git_source, repository: repository, client: client).call

    expect(result.services.one?).to be(true)
    expect(result.services.first).to include(
      "builder" => "dockerfile",
      "source_revision" => commit_sha,
      "subtype" => "web"
    )
    expect(result.services.first["dockerfile_path"]).to eq("docker/production.Dockerfile")
    expect(result.evidence.first).to include(path: "railway.toml", format: "railway.toml", confidence: "high")
  end

  it "composes independent manifests in a monorepo" do
    stub_tree("web/railway.toml", "worker/railway.toml")
    stub_content("web/railway.toml", "[build]\nbuilder = \"DOCKERFILE\"\n")
    stub_content("worker/railway.toml", "[build]\nbuilder = \"NIXPACKS\"\n")

    result = described_class.new(git_source: git_source, repository: repository, client: client).call

    expect(result.services.map { |service| service["name"] }).to contain_exactly("web", "worker")
    expect(result.services.map { |service| service["root_directory"] }).to contain_exactly("web", "worker")
  end

  it "discovers conventional apps with a registered web subtype" do
    stub_tree("package.json", "Gemfile", "Dockerfile")
    stub_content("package.json", JSON.generate(name: "storefront"))
    stub_content("Gemfile", "source 'https://rubygems.org'\n")
    stub_content("Dockerfile", "FROM ruby:3.4\n")

    result = described_class.new(git_source: git_source, repository: repository, client: client).call

    expect(result.services.map { |service| service["subtype"] }).to eq([ "web" ])
    expect(result.services.first).to include(
      "name" => "storefront",
      "builder" => "dockerfile",
      "category" => "app"
    )
  end

  it "uses a native RailDock manifest as authoritative and reports compatibility files as a note" do
    stub_tree("raildock.json", "railway.toml")
    stub_content("raildock.json", JSON.generate(name: "storefront", services: [ { name: "web", category: "app", subtype: "web" } ]))

    result = described_class.new(git_source: git_source, repository: repository, client: client).call

    expect(result.services.map { |service| service["name"] }).to eq([ "web" ])
    expect(result.conflicts).to be_empty
    expect(result.warnings.join).to include("used the native manifest")
  end

  it "detects a static frontend and records its publish directory" do
    stub_tree("package.json")
    stub_content("package.json", JSON.generate(
      "scripts" => { "dev" => "vite", "build" => "tsc && vite build" },
      "devDependencies" => { "vite" => "^6.0.0" }
    ))

    result = described_class.new(git_source: git_source, repository: repository, client: client).call

    expect(result.services.first).to include("publish_directory" => "dist")
    expect(result.services.first["builder"]).to be_nil
    expect(result.evidence.first[:decision]).to include("Static vite")
  end

  it "does not mark a server-rendered Next app as static" do
    stub_tree("package.json")
    stub_content("package.json", JSON.generate(
      "scripts" => { "build" => "next build" },
      "dependencies" => { "next" => "^15.0.0" }
    ))

    result = described_class.new(git_source: git_source, repository: repository, client: client).call

    expect(result.services.first).not_to have_key("publish_directory")
  end

  it "lists variable names documented in example dotenv files" do
    stub_tree("package.json", ".env.example")
    stub_content("package.json", JSON.generate(name: "storefront"))
    stub_content(".env.example", <<~ENV)
      # comment
      DATABASE_URL=postgres://localhost/app
      export REDIS_URL=redis://localhost:6379
      API_KEY=
      not a variable
    ENV

    result = described_class.new(git_source: git_source, repository: repository, client: client).call

    expect(result.services.first["env_keys"]).to eq(%w[API_KEY DATABASE_URL REDIS_URL])
    expect(result.canonical_manifest).not_to include("env_keys")
  end

  it "never reads a real .env file" do
    stub_tree("package.json", ".env")
    stub_content("package.json", JSON.generate(name: "storefront"))

    result = described_class.new(git_source: git_source, repository: repository, client: client).call

    expect(result.services.first["env_keys"]).to eq([])
    expect(client).not_to have_received(:contents).with(repository, path: ".env", ref: commit_sha)
  end

  it "discovers a plain static site from a bare index.html at the repository root" do
    stub_tree("index.html", "styles.css")

    result = described_class.new(git_source: git_source, repository: repository, client: client).call

    expect(result.services.map { |service| service["category"] }).to eq([ "app" ])
    expect(result.services.first).to include(
      "name" => "storefront",
      "plain_static" => true
    )
    expect(result.services.first).not_to have_key("publish_directory")
    expect(result.services.first["builder"]).to be_nil
    expect(result.evidence.first[:decision]).to include("no build step")
  end

  it "keeps plain_static in the canonical manifest but drops env_keys" do
    stub_tree("index.html")

    result = described_class.new(git_source: git_source, repository: repository, client: client).call

    manifest = JSON.generate(result.canonical_manifest)
    expect(manifest).to include("plain_static")
    expect(manifest).not_to include("env_keys")
  end

  it "does not treat a root index.html next to a Dockerfile as plain static" do
    stub_tree("index.html", "Dockerfile")
    stub_content("Dockerfile", "FROM nginx:alpine\n")

    result = described_class.new(git_source: git_source, repository: repository, client: client).call

    expect(result.services.first["builder"]).to eq("dockerfile")
    expect(result.services.first).not_to have_key("plain_static")
  end

  it "does not discover a nested index.html as a plain static service" do
    stub_tree("public/index.html", "package.json")
    stub_content("package.json", JSON.generate(name: "storefront"))

    result = described_class.new(git_source: git_source, repository: repository, client: client).call

    expect(result.services.map { |service| service["name"] }).to eq([ "storefront" ])
    expect(result.services.first).not_to have_key("plain_static")
  end

  def stub_tree(*paths)
    entries = paths.map { |path| OpenStruct.new(type: "blob", path: path) }
    allow(client).to receive(:tree).with(repository, commit_sha, recursive: true).and_return(
      OpenStruct.new(truncated: false, tree: entries)
    )
  end

  def stub_content(path, body)
    allow(client).to receive(:contents).with(repository, path: path, ref: commit_sha).and_return(
      OpenStruct.new(content: Base64.strict_encode64(body))
    )
  end
end
