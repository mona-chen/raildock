require "rails_helper"
require "ostruct"

RSpec.describe StaticSiteProbe do
  let(:repository) { "acme/storefront" }
  let(:ref) { "main" }
  let(:client) { double("Octokit client") }
  let(:probe) { described_class.new(client: client, repository: repository, ref: ref) }

  let(:package_json) do
    JSON.generate(
      "dependencies" => { "react" => "^19", "vite" => "^6" },
      "scripts" => { "build" => "vite build" }
    )
  end

  def stub_tree(*paths, truncated: false)
    entries = paths.map { |path| OpenStruct.new(type: "blob", path: path) }
    allow(client).to receive(:tree).with(repository, ref, recursive: true).and_return(
      OpenStruct.new(truncated: truncated, tree: entries)
    )
  end

  def stub_content(path, body)
    allow(client).to receive(:contents).with(repository, path: path, ref: ref).and_return(
      OpenStruct.new(content: Base64.strict_encode64(body))
    )
  end

  it "detects a Vite frontend and its default publish directory" do
    stub_tree("package.json")
    stub_content("package.json", package_json)

    result = probe.detect

    expect(result.framework).to eq("vite")
    expect(result.publish_directory).to eq("dist")
    expect(result.config).to eq("publishDirectory" => "dist", "spaFallback" => true)
  end

  it "reads the framework config that moves the publish directory" do
    stub_tree("package.json", "vite.config.ts")
    stub_content("package.json", package_json)
    stub_content("vite.config.ts", "export default { build: { outDir: 'build' } }")

    expect(probe.detect.publish_directory).to eq("build")
  end

  it "carries the Node version the repo pins" do
    stub_tree("package.json")
    stub_content("package.json", JSON.generate(
      "dependencies" => { "vite" => "^6" },
      "scripts" => { "build" => "vite build" },
      "engines" => { "node" => ">=20" }
    ))

    expect(probe.detect.node_version).to eq("20")
  end

  it "leaves repos that declare their own process alone" do
    stub_tree("package.json", "Procfile")
    stub_content("package.json", package_json)
    stub_content("Procfile", "web: node server.js\n")

    expect(probe.detect).to be_nil
  end

  it "leaves repos that build from a Dockerfile alone" do
    stub_tree("package.json", "Dockerfile")

    expect(probe.detect).to be_nil
  end

  it "leaves server frameworks alone" do
    stub_tree("package.json")
    stub_content("package.json", JSON.generate(
      "dependencies" => { "@sveltejs/kit" => "^2" },
      "scripts" => { "build" => "vite build" }
    ))

    expect(probe.detect).to be_nil
  end

  it "scopes the probe to the configured root directory" do
    stub_tree("package.json", "web/package.json")
    stub_content("web/package.json", package_json)
    stub_content("package.json", JSON.generate("dependencies" => { "express" => "^5" }))

    expect(probe.detect(root_directory: "web").publish_directory).to eq("dist")
    expect(probe.detect(root_directory: nil)).to be_nil
  end

  it "returns nil when the manifest is missing or invalid" do
    # The root holds only a Vite config, which cannot identify a framework alone.
    stub_tree("vite.config.ts")

    expect(probe.detect).to be_nil

    stub_tree("package.json")
    stub_content("package.json", "{ not json")

    expect(probe.detect).to be_nil
  end

  it "returns nil when the tree cannot be listed or is truncated" do
    allow(client).to receive(:tree).and_raise(Octokit::NotFound)
    expect(probe.detect).to be_nil

    stub_tree("package.json", truncated: true)
    expect(probe.detect).to be_nil
  end
end
