require 'rails_helper'

RSpec.describe StorageMount, type: :model do
  describe "validations" do
    subject { build(:storage_mount) }

    it { is_expected.to validate_presence_of(:host_path) }
    it { is_expected.to validate_presence_of(:container_path) }
    it { is_expected.to validate_uniqueness_of(:host_path).scoped_to(:service_id) }
  end

  describe "associations" do
    it { is_expected.to belong_to(:service) }
  end

  describe "uniqueness edge cases" do
    let(:service) { create(:service) }

    it "allows the same host_path on different services" do
      create(:storage_mount, host_path: "/var/data", service: service)
      other_service = create(:service)
      other_mount = build(:storage_mount, host_path: "/var/data", service: other_service)
      expect(other_mount).to be_valid
    end

    it "prevents duplicate host_paths on the same service" do
      create(:storage_mount, host_path: "/var/data", service: service)
      duplicate = build(:storage_mount, host_path: "/var/data", service: service)
      expect(duplicate).not_to be_valid
    end
  end
end
