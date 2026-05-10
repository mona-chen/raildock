require 'rails_helper'

RSpec.describe Domain, type: :model do
  describe "validations" do
    subject { build(:domain) }

    it { is_expected.to validate_presence_of(:hostname) }
    it { is_expected.to validate_uniqueness_of(:hostname).scoped_to(:service_id) }
    it { is_expected.to validate_numericality_of(:port).only_integer.is_greater_than(0).is_less_than_or_equal_to(65_535) }
  end

  describe "associations" do
    it { is_expected.to belong_to(:service) }
  end

  describe "port validation edge cases" do
    it "is invalid with port 0" do
      domain = build(:domain, port: 0)
      expect(domain).not_to be_valid
      expect(domain.errors[:port]).to include("must be greater than 0")
    end

    it "is invalid with a negative port" do
      domain = build(:domain, port: -1)
      expect(domain).not_to be_valid
    end

    it "is invalid with port 65536" do
      domain = build(:domain, port: 65_536)
      expect(domain).not_to be_valid
      expect(domain.errors[:port]).to include("must be less than or equal to 65535")
    end

    it "is valid with port 1" do
      domain = build(:domain, port: 1)
      expect(domain).to be_valid
    end

    it "is valid with port 65535" do
      domain = build(:domain, port: 65_535)
      expect(domain).to be_valid
    end
  end

  describe "hostname uniqueness" do
    let(:service) { create(:service) }

    it "allows the same hostname on different services" do
      create(:domain, hostname: "example.com", service: service)
      other_service = create(:service)
      other_domain = build(:domain, hostname: "example.com", service: other_service)
      expect(other_domain).to be_valid
    end
  end
end
