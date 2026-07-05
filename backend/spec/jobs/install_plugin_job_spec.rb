require 'rails_helper'

RSpec.describe InstallPluginJob, type: :job do
  let(:manifest_url) { "https://example.com/plugin.yml" }
  let(:manifest) do
    {
      "slug" => "external-test",
      "name" => "External Test",
      "category" => "tool",
      "subtypes" => [
        { "subtype" => "custom", "name" => "Custom", "service_type" => "service", "capabilities" => ["docker_deploy"] }
      ],
      "builders" => [
        { "slug" => "custom-builder", "name" => "Custom Builder", "dokku_builder" => "dockerfile", "source_types" => ["git"] }
      ]
    }
  end

  it "registers an external plugin from a manifest" do
    manifest_double = instance_double(PluginManifest, fetch: manifest, errors: [])
    allow(PluginManifest).to receive(:new).with(manifest_url).and_return(manifest_double)

    expect {
      InstallPluginJob.perform_now(source_url: manifest_url)
    }.to change(Plugin, :count).by(1)

    plugin = Plugin.find_by(slug: "external-test")
    expect(plugin).to be_enabled
    expect(plugin.service_subtypes.pluck(:subtype)).to include("custom")
    expect(plugin.builders.pluck(:slug)).to include("custom-builder")
  end

  it "raises when the manifest is invalid" do
    manifest_double = instance_double(PluginManifest, fetch: nil, errors: ["Missing slug"])
    allow(PluginManifest).to receive(:new).with(manifest_url).and_return(manifest_double)

    expect {
      InstallPluginJob.perform_now(source_url: manifest_url)
    }.to raise_error(/Manifest fetch\/validation failed/)
  end
end
