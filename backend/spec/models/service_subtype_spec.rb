require 'rails_helper'

RSpec.describe ServiceSubtype, type: :model do
  describe "validations" do
    it { is_expected.to validate_presence_of(:subtype) }
    it { is_expected.to validate_uniqueness_of(:subtype) }
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:service_type) }
    it { is_expected.to validate_inclusion_of(:service_type).in_array(%w[app database cache queue search service]) }
  end

  describe "associations" do
    it { is_expected.to belong_to(:plugin) }
    it { is_expected.to have_many(:services).with_foreign_key("subtype").with_primary_key("subtype") }
  end

  describe "built-in subtypes" do
    it "finds postgres with the right capabilities" do
      st = ServiceSubtype.find_by(subtype: "postgres")
      expect(st).to be_present
      expect(st).to have_capability(:create)
      expect(st).to have_capability(:backup)
      expect(st).to have_capability(:point_in_time_recovery)
      expect(st.dokku_command(:create)).to eq("postgres:create")
      expect(st.url_var).to eq("DATABASE_URL")
      expect(st.sslmode).to eq("disable")
    end

    it "uses mysql command namespace for mariadb" do
      st = ServiceSubtype.find_by(subtype: "mariadb")
      expect(st.dokku_command(:create)).to eq("mysql:create")
    end
  end

  describe "#has_capability?" do
    it "returns false for missing capabilities" do
      st = ServiceSubtype.find_by(subtype: "postgres")
      expect(st).not_to have_capability(:unknown)
    end
  end
end
