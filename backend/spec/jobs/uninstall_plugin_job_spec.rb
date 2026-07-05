require 'rails_helper'

RSpec.describe UninstallPluginJob, type: :job do
  let!(:plugin) { create(:plugin, slug: "external-test") }
  let!(:subtype) { plugin.service_subtypes.create!(subtype: "custom", name: "Custom", service_type: "service", capabilities: [ "docker_deploy" ]) }
  let!(:builder) { plugin.builders.create!(slug: "custom-builder", name: "Custom Builder", dokku_builder: "dockerfile", source_types: [ "git" ]) }

  it "uninstalls an external plugin and its subtypes/builders" do
    expect {
      UninstallPluginJob.perform_now(plugin.id)
    }.to change(Plugin, :count).by(-1)

    expect(ServiceSubtype.find_by(id: subtype.id)).to be_nil
    expect(Builder.find_by(id: builder.id)).to be_nil
  end

  it "refuses to uninstall a built-in plugin" do
    plugin.update!(status: "built_in")

    expect {
      UninstallPluginJob.perform_now(plugin.id)
    }.to raise_error(/Built-in plugins cannot be uninstalled/)
  end

  it "refuses to uninstall when subtypes are in use" do
    project = create(:project)
    create(:service, project: project, subtype: "custom", builder: nil)

    expect {
      UninstallPluginJob.perform_now(plugin.id)
    }.to raise_error(/Plugin subtypes are still in use/)
  end

  it "refuses to uninstall when builders are in use" do
    project = create(:project)
    create(:service, project: project, subtype: "web", builder: "custom-builder")

    expect {
      UninstallPluginJob.perform_now(plugin.id)
    }.to raise_error(/Plugin builders are still in use/)
  end
end
