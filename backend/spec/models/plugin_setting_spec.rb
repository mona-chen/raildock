require 'rails_helper'

RSpec.describe PluginSetting, type: :model do
  let(:plugin) { create(:plugin) }

  it "is valid with key and value" do
    setting = PluginSetting.new(plugin: plugin, key: "endpoint", value: "https://example.com")
    expect(setting).to be_valid
  end

  it "requires a key" do
    setting = PluginSetting.new(plugin: plugin, value: "x")
    expect(setting).not_to be_valid
  end

  it "requires key uniqueness scoped to plugin" do
    PluginSetting.create!(plugin: plugin, key: "endpoint", value: "a")
    duplicate = PluginSetting.new(plugin: plugin, key: "endpoint", value: "b")
    expect(duplicate).not_to be_valid
  end
end
