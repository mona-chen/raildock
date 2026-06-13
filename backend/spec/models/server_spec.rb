require 'rails_helper'

RSpec.describe Server, type: :model do
  describe "external proxy settings" do
    it "requires a network in external mode" do
      server = build(:server, proxy_mode: "external", external_proxy_network: nil)

      expect(server).not_to be_valid
      expect(server.errors[:external_proxy_network]).to be_present
    end

    it "does not require an external network in managed mode" do
      server = build(:server, proxy_mode: "managed", external_proxy_network: nil)

      expect(server).to be_valid
    end
  end
  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:host) }
  end

  describe "associations" do
    it { is_expected.to have_many(:projects).dependent(:nullify) }
  end

  describe "enums" do
    it "defines status enum with correct values" do
      expect(described_class.statuses.keys).to contain_exactly("connected", "disconnected", "error")
    end

    it "defaults status to disconnected" do
      server = described_class.new
      expect(server.status).to eq("disconnected")
    end
  end

  describe "constants" do
    it "defines PROXY_TYPES" do
      expect(described_class::PROXY_TYPES).to eq(%w[nginx traefik caddy haproxy openresty])
    end
  end

  describe "#default_proxy" do
    it "returns the stored value when present" do
      server = build(:server, default_proxy: "traefik")
      expect(server.default_proxy).to eq("traefik")
    end

    it "returns 'traefik' when stored value is blank" do
      server = build(:server, default_proxy: nil)
      expect(server.default_proxy).to eq("traefik")

      server = build(:server, default_proxy: "")
      expect(server.default_proxy).to eq("traefik")
    end
  end

  describe "#disk_usage" do
    it "returns a hash with used and total values" do
      server = build(:server, disk_used: 40, disk_total: 100)
      expect(server.disk_usage).to eq({ used: 40, total: 100 })
    end

    it "returns default values when not set" do
      server = build(:server, disk_used: nil, disk_total: nil)
      expect(server.disk_usage).to eq({ used: 0, total: 0 })
    end
  end

  describe "#memory_usage" do
    it "returns a hash with used and total values" do
      server = build(:server, memory_used: 64, memory_total: 128)
      expect(server.memory_usage).to eq({ used: 64, total: 128 })
    end

    it "returns default values when not set" do
      server = build(:server, memory_used: nil, memory_total: nil)
      expect(server.memory_usage).to eq({ used: 0, total: 0 })
    end
  end

  describe "projects dependency" do
    it "nullifies associated projects when destroyed" do
      server = create(:server)
      project = create(:project, server: server)
      expect { server.destroy }.not_to raise_error
      expect(project.reload.server_id).to be_nil
    end
  end
end
