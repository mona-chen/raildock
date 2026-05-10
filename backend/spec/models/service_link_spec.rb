require 'rails_helper'

RSpec.describe ServiceLink, type: :model do
  describe "validations" do
    subject { build(:service_link) }

    it { is_expected.to validate_uniqueness_of(:from_service_id).scoped_to(:to_service_id) }

    it "is invalid when from_service equals to_service" do
      service = create(:service)
      link = build(:service_link, from_service: service, to_service: service)
      expect(link).not_to be_valid
      expect(link.errors[:to_service]).to include("cannot link to itself")
    end

    it "is valid when linking two different services" do
      from = create(:service)
      to = create(:service)
      link = build(:service_link, from_service: from, to_service: to)
      expect(link).to be_valid
    end

    it "is invalid when creating a duplicate link" do
      from = create(:service)
      to = create(:service)
      create(:service_link, from_service: from, to_service: to)
      duplicate = build(:service_link, from_service: from, to_service: to)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:from_service_id]).to include("has already been taken")
    end
  end

  describe "associations" do
    it { is_expected.to belong_to(:from_service).class_name("Service") }
    it { is_expected.to belong_to(:to_service).class_name("Service") }
  end
end
