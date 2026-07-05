require 'rails_helper'

RSpec.describe Plugin, type: :model do
  describe "validations" do
    it { is_expected.to validate_presence_of(:slug) }
    it { is_expected.to validate_uniqueness_of(:slug) }
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:category) }
    it { is_expected.to validate_inclusion_of(:category).in_array(%w[database cache queue search service tool]) }
    it { is_expected.to validate_inclusion_of(:status).in_array(%w[built_in enabled disabled]) }
  end

  describe "associations" do
    it { is_expected.to have_many(:service_subtypes).dependent(:destroy) }
  end

  describe "scopes" do
    it "returns built_in plugins" do
      built_in = Plugin.find_by(slug: "core-databases")
      expect(Plugin.built_in).to include(built_in)
    end

    it "returns enabled plugins including built-ins" do
      built_in = Plugin.find_by(slug: "core-databases")
      expect(Plugin.enabled).to include(built_in)
    end
  end

  describe "#built_in? and #enabled?" do
    it "identifies built-in plugins" do
      plugin = Plugin.find_by(slug: "core-databases")
      expect(plugin).to be_built_in
      expect(plugin).to be_enabled
    end
  end
end
