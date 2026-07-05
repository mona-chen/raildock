require 'rails_helper'

RSpec.describe PluginRegistry do
  describe ".seed!" do
    it "is idempotent" do
      expect { described_class.seed! }.not_to change(Plugin, :count)
      expect { described_class.seed! }.not_to change(ServiceSubtype, :count)
    end

    it "creates built-in plugins if missing" do
      Plugin.where(slug: "core-databases").destroy_all
      expect { described_class.seed! }.to change(Plugin, :count).by(1)
      expect(Plugin.find_by(slug: "core-databases")).to be_present
    end
  end

  describe ".find_subtype" do
    it "returns the postgres subtype" do
      st = described_class.find_subtype("postgres")
      expect(st).to be_a(ServiceSubtype)
      expect(st.subtype).to eq("postgres")
    end

    it "returns nil for unknown subtypes" do
      expect(described_class.find_subtype("unknown")).to be_nil
    end
  end

  describe ".subtypes_for" do
    it "returns database subtypes" do
      subtypes = described_class.subtypes_for("database").pluck(:subtype)
      expect(subtypes).to include("postgres", "mysql", "mariadb", "mongo")
    end
  end

  describe ".has_capability?" do
    it "returns true for postgres backup" do
      expect(described_class.has_capability?("postgres", :backup)).to be(true)
    end

    it "returns false for redis point_in_time_recovery" do
      expect(described_class.has_capability?("redis", :point_in_time_recovery)).to be(false)
    end
  end
end
