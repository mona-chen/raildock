require 'rails_helper'

RSpec.describe Project, type: :model do
  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }

    it "is valid with a recognized environment" do
      %w[production staging development].each do |env|
        expect(build(:project, environment: env)).to be_valid
      end
    end

    it "is invalid with an unrecognized environment" do
      project = build(:project, environment: "testing")
      expect(project).not_to be_valid
      expect(project.errors[:environment]).to include("is not included in the list")
    end
  end

  describe "associations" do
    it { is_expected.to belong_to(:server).optional }
    it { is_expected.to have_many(:services).dependent(:destroy) }
    it { is_expected.to have_many(:activity_events).dependent(:destroy) }
  end

  describe "#service_ids" do
    let(:project) { create(:project) }

    it "returns an empty array when no services exist" do
      expect(project.service_ids).to eq([])
    end

    it "returns the ids of associated services" do
      service1 = create(:service, project: project)
      service2 = create(:service, project: project)
      expect(project.service_ids).to contain_exactly(service1.id, service2.id)
    end
  end

  describe "#shared_vars" do
    it "returns the stored value when present" do
      project = build(:project, shared_vars: ["DATABASE_URL"])
      expect(project.shared_vars).to eq(["DATABASE_URL"])
    end

    it "returns an empty array when nil" do
      project = build(:project, shared_vars: nil)
      expect(project.shared_vars).to eq([])
    end

    it "returns an empty array when default" do
      project = described_class.new
      expect(project.shared_vars).to eq([])
    end
  end

  describe "#as_json" do
    let(:project) { create(:project) }

    it "includes service_ids" do
      create(:service, project: project)
      json = project.as_json
      expect(json).to have_key("service_ids")
      expect(json["service_ids"]).to eq(project.service_ids)
    end

    it "includes shared_vars" do
      json = project.as_json
      expect(json).to have_key("shared_vars")
    end
  end

  describe "dependent destroy" do
    it "destroys associated services on destroy" do
      project = create(:project)
      service = create(:service, project: project)
      expect { project.destroy }.to change { Service.count }.by(-1)
      expect(Service.exists?(service.id)).to be false
    end

    it "destroys associated activity_events on destroy" do
      project = create(:project)
      event = create(:activity_event, project: project)
      expect { project.destroy }.to change { ActivityEvent.count }.by(-1)
      expect(ActivityEvent.exists?(event.id)).to be false
    end
  end
end
