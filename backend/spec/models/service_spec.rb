require 'rails_helper'

RSpec.describe Service, type: :model do
  describe ".repo_full_name" do
    it "normalizes GitHub full names and clone URLs" do
      expect(described_class.repo_full_name("acme/app")).to eq("acme/app")
      expect(described_class.repo_full_name("https://github.com/acme/app.git")).to eq("acme/app")
      expect(described_class.repo_full_name("git@github.com:acme/app.git")).to eq("acme/app")
    end
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }

    it "is valid with recognized service_types" do
      %w[app database cache queue search service].each do |type|
        expect(build(:service, service_type: type)).to be_valid
      end
    end

    it "raises ArgumentError with an unrecognized service_type" do
      expect {
        build(:service, service_type: "unknown")
      }.to raise_error(ArgumentError, "'unknown' is not a valid service_type")
    end

    it "is valid with recognized statuses" do
      %w[running stopped deploying error building].each do |status|
        expect(build(:service, status: status)).to be_valid
      end
    end

    it "raises ArgumentError with an unrecognized status" do
      expect {
        build(:service, status: "crashed")
      }.to raise_error(ArgumentError, "'crashed' is not a valid status")
    end
  end

  describe "associations" do
    it { is_expected.to belong_to(:project) }
    it { is_expected.to have_many(:environment_variables).dependent(:destroy) }
    it { is_expected.to have_many(:domains).dependent(:destroy) }
    it { is_expected.to have_many(:storage_mounts).dependent(:destroy) }
    it { is_expected.to have_many(:deployments).dependent(:destroy) }
    it { is_expected.to have_many(:process_types).dependent(:destroy) }
    it { is_expected.to have_many(:outgoing_links).class_name("ServiceLink").with_foreign_key("from_service_id").dependent(:destroy) }
    it { is_expected.to have_many(:incoming_links).class_name("ServiceLink").with_foreign_key("to_service_id").dependent(:destroy) }
    it { is_expected.to have_many(:linked_services).through(:outgoing_links).source(:to_service) }
  end

  describe "enums" do
    it "defines service_type with prefix" do
      expect(described_class.service_types.keys).to contain_exactly("app", "database", "cache", "queue", "search", "service")
      service = create(:service, service_type: :app)
      expect(service.service_type_app?).to be true
    end

    it "defines status enum" do
      expect(described_class.statuses.keys).to contain_exactly("running", "stopped", "deploying", "error", "building")
    end

    it "defines builder enum" do
      expect(described_class.builders.keys).to contain_exactly("herokuish", "pack", "dockerfile", "nixpacks", "railpack", "lambda", "null_builder")
    end

    it "defines restart_policy enum" do
      expect(described_class.restart_policies.keys).to contain_exactly("never", "on_failure", "always", "unless_stopped")
    end
  end

  describe "scopes" do
    let!(:app_service) { create(:service, service_type: :app) }
    let!(:db_service) { create(:service, service_type: :database) }
    let!(:cache_service) { create(:service, service_type: :cache) }

    describe ".apps" do
      it "returns only app services" do
        expect(described_class.apps).to contain_exactly(app_service)
      end
    end

    describe ".databases" do
      it "returns only database services" do
        expect(described_class.databases).to contain_exactly(db_service)
      end
    end

    describe ".caches" do
      it "returns only cache services" do
        expect(described_class.caches).to contain_exactly(cache_service)
      end
    end
  end

  describe "callbacks" do
    describe "#generate_dokku_app_name" do
      it "generates a dokku_app_name before create with a hex suffix" do
        project = create(:project, name: "My Project")
        service = create(:service, project: project, name: "Web App", dokku_app_name: nil)
        expect(service.dokku_app_name).to match(/\Amy-project-web-app-[a-f0-9]{8}\z/)
      end

      it "does not override an existing dokku_app_name" do
        service = create(:service, dokku_app_name: "custom-name")
        expect(service.dokku_app_name).to eq("custom-name")
      end
    end
  end

  describe "#linked_service_ids" do
    let(:service) { create(:service) }
    let(:linked_service) { create(:service) }

    it "returns an empty array when no links exist" do
      expect(service.linked_service_ids).to eq([])
    end

    it "returns the ids of linked services" do
      create(:service_link, from_service: service, to_service: linked_service)
      expect(service.linked_service_ids).to contain_exactly(linked_service.id)
    end
  end

  describe "#logs" do
    let(:service) { create(:service) }

    it "returns an empty array when no deployments exist" do
      expect(service.logs).to eq([])
    end

    it "returns log entries from recent deployments" do
      deployment = create(:deployment, service: service, status: :succeeded, started_at: 1.hour.ago)
      logs = service.logs
      expect(logs).to be_an(Array)
      expect(logs.first).to include(:timestamp, :process_type, :message)
      expect(logs.first[:process_type]).to eq("deploy")
      expect(logs.first[:message]).to eq("Deployment succeeded")
    end

    it "limits to the 10 most recent deployments" do
      create_list(:deployment, 12, service: service)
      expect(service.logs.length).to eq(10)
    end
  end

  describe "#backups" do
    let(:service) { create(:service) }

    it "returns an empty array" do
      expect(service.backups).to eq([])
    end
  end

  describe "#as_json" do
    let(:service) { create(:service) }

    it "includes linked_service_ids" do
      json = service.as_json
      expect(json).to have_key("linked_service_ids")
    end

    it "includes logs" do
      json = service.as_json
      expect(json).to have_key("logs")
    end

    it "includes backups" do
      json = service.as_json
      expect(json).to have_key("backups")
    end

    it "includes config as a merged key" do
      service = create(:service, config: { "FOO" => "bar" })
      json = service.as_json
      expect(json["config"]).to eq({ "FOO" => "bar" })
    end

    it "includes nested associations" do
      create(:environment_variable, service: service)
      create(:domain, service: service)
      create(:storage_mount, service: service)
      create(:process_type, service: service)

      json = service.as_json
      expect(json).to have_key("environment_variables")
      expect(json).to have_key("domains")
      expect(json).to have_key("storage_mounts")
      expect(json).to have_key("process_types")
    end
  end

  describe "dependent destroy" do
    let(:service) { create(:service) }

    it "destroys environment_variables on destroy" do
      create(:environment_variable, service: service)
      expect { service.destroy }.to change { EnvironmentVariable.count }.by(-1)
    end

    it "destroys domains on destroy" do
      create(:domain, service: service)
      expect { service.destroy }.to change { Domain.count }.by(-1)
    end

    it "destroys storage_mounts on destroy" do
      create(:storage_mount, service: service)
      expect { service.destroy }.to change { StorageMount.count }.by(-1)
    end

    it "destroys deployments on destroy" do
      create(:deployment, service: service)
      expect { service.destroy }.to change { Deployment.count }.by(-1)
    end

    it "destroys process_types on destroy" do
      create(:process_type, service: service)
      expect { service.destroy }.to change { ProcessType.count }.by(-1)
    end

    it "destroys outgoing service_links on destroy" do
      other = create(:service)
      create(:service_link, from_service: service, to_service: other)
      expect { service.destroy }.to change { ServiceLink.count }.by(-1)
    end

    it "destroys incoming service_links on destroy" do
      other = create(:service)
      create(:service_link, from_service: other, to_service: service)
      expect { service.destroy }.to change { ServiceLink.count }.by(-1)
    end
  end
end
