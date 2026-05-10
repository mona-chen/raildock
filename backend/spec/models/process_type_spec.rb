require 'rails_helper'

RSpec.describe ProcessType, type: :model do
  describe "validations" do
    subject { build(:process_type) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_uniqueness_of(:name).scoped_to(:service_id) }
    it { is_expected.to validate_numericality_of(:quantity).is_greater_than_or_equal_to(0) }
  end

  describe "associations" do
    it { is_expected.to belong_to(:service) }
  end

  describe "quantity validation edge cases" do
    it "is invalid with a negative quantity" do
      process_type = build(:process_type, quantity: -1)
      expect(process_type).not_to be_valid
      expect(process_type.errors[:quantity]).to include("must be greater than or equal to 0")
    end

    it "is valid with quantity 0" do
      process_type = build(:process_type, quantity: 0)
      expect(process_type).to be_valid
    end

    it "is valid with a positive quantity" do
      process_type = build(:process_type, quantity: 5)
      expect(process_type).to be_valid
    end
  end

  describe "name uniqueness" do
    let(:service) { create(:service) }

    it "allows the same name on different services" do
      create(:process_type, name: "web", service: service)
      other_service = create(:service)
      other_process = build(:process_type, name: "web", service: other_service)
      expect(other_process).to be_valid
    end

    it "prevents duplicate names on the same service" do
      create(:process_type, name: "web", service: service)
      duplicate = build(:process_type, name: "web", service: service)
      expect(duplicate).not_to be_valid
    end
  end
end
