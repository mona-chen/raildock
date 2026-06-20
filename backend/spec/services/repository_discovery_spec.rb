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

  it "uses a native RailDock manifest as authoritative and reports compatibility files as a note" do
    stub_tree("raildock.json", "railway.toml")
    stub_content("raildock.json", JSON.generate(name: "storefront", services: [ { name: "web", category: "app", subtype: "web" } ]))

    result = described_class.new(git_source: git_source, repository: repository, client: client).call

    expect(result.services.map { |service| service["name"] }).to eq([ "web" ])
    expect(result.conflicts).to be_empty
    expect(result.warnings.join).to include("used the native manifest")
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
