require 'rails_helper'

RSpec.describe EnvironmentVariable, type: :model do
  describe "validations" do
    subject { build(:environment_variable) }

    it { is_expected.to validate_presence_of(:key) }
    it { is_expected.to validate_presence_of(:value) }
    it { is_expected.to validate_uniqueness_of(:key).scoped_to(:service_id) }
  end

  describe "associations" do
    it { is_expected.to belong_to(:service) }
  end

  describe "uniqueness edge cases" do
    let(:service) { create(:service) }

    it "allows the same key for different services" do
      create(:environment_variable, key: "DATABASE_URL", service: service)
      other_service = create(:service)
      other_var = build(:environment_variable, key: "DATABASE_URL", service: other_service)
      expect(other_var).to be_valid
    end

    it "prevents duplicate keys on the same service" do
      create(:environment_variable, key: "SECRET", service: service)
      duplicate = build(:environment_variable, key: "SECRET", service: service)
      expect(duplicate).not_to be_valid
    end
  end
end
