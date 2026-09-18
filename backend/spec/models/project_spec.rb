require 'rails_helper'

RSpec.describe Project, type: :model do
  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }

    # The label mirrors the project's primary environment, which is free-form
    # now that environments are first-class rows.
    it "accepts an arbitrary primary environment label" do
      %w[production staging development qa-sandbox].each do |env|
        expect(build(:project, environment: env)).to be_valid
      end
    end

    it "defaults a blank primary environment label to production" do
      project = build(:project, environment: nil)

      expect(project).to be_valid
      expect(project.environment).to eq("production")
    end
  end

  describe "associations" do
    it { is_expected.to belong_to(:server).optional }
    it { is_expected.to have_many(:services).dependent(:destroy) }
    it { is_expected.to have_many(:environments).dependent(:delete_all) }
    it { is_expected.to have_many(:activity_events).dependent(:destroy) }
  end

  describe "#default_environment" do
    it "returns the production environment created with the project" do
      project = create(:project)

      expect(project.default_environment.name).to eq("production")
      expect(project.default_environment).to be_default
    end
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
      project = build(:project, shared_vars: [ "DATABASE_URL" ])
      expect(project.shared_vars).to eq([ "DATABASE_URL" ])
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

  describe "#shared_var_map" do
    it "normalizes current object entries and legacy KEY=value entries" do
      project = build(
        :project,
        shared_vars: [
          { "key" => "API_KEY", "value" => "secret" },
          "LEGACY=value"
        ]
      )

      expect(project.shared_var_map).to eq(
        "API_KEY" => "secret",
        "LEGACY" => "value"
      )
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

  describe "#manifest_synced?" do
    def synced_project(**attrs)
      create(:project, manifest_last_synced_at: 1.hour.ago, manifest_last_applied_at: Time.current, **attrs)
    end

    it "is true when the last apply came after the last sync" do
      expect(synced_project.manifest_synced?).to be(true)
    end

    it "is false when the manifest has not been applied" do
      expect(create(:project).manifest_synced?).to be(false)
    end

    it "is false when drift was detected, even if an apply came after the sync" do
      expect(synced_project(manifest_drift_detected: true).manifest_synced?).to be(false)
    end
  end

  describe "dependent destroy" do
    it "refuses to destroy a project that still owns services unless explicitly allowed" do
      project = create(:project)
      create(:service, project: project)

      # #destroy swallows the callback's RecordNotDestroyed (Rails semantics);
      # #destroy! surfaces it. Either way, nothing is removed.
      expect(project.destroy).to be(false)
      expect(Project.exists?(project.id)).to be(true)

      expect { project.destroy! }.to raise_error(ActiveRecord::RecordNotDestroyed)
      expect(Project.exists?(project.id)).to be(true)
      expect(project.services.count).to eq(1)
    end

    it "destroys associated services and environments on destroy once resources are allowed" do
      project = create(:project)
      service = create(:service, project: project)
      staging = project.environments.create!(name: "staging")
      project.allow_resource_destruction = true
      allow_any_instance_of(DokkuEngine).to receive(:app_destroy).and_return({ success: true })

      expect { project.destroy }
        .to change { Service.count }.by(-1)
        .and change { Environment.count }.by(-2)

      expect(Service.exists?(service.id)).to be false
      expect(Environment.exists?(staging.id)).to be false
    end

    it "keeps the project when Dokku could not remove its resources" do
      project = create(:project)
      create(:service, project: project)
      allow_any_instance_of(DokkuEngine).to receive(:app_destroy).and_return({ success: false, output: "SSH error" })

      expect { project.destroy_with_resources!(confirmed: true) }.to raise_error(ActiveRecord::RecordNotDestroyed, /Nothing was deleted/)

      expect(Project.exists?(project.id)).to be true
      expect(project.services.count).to eq(1)
    end

    it "reports what a project destruction would take with it" do
      project = create(:project)
      create(:service, :database, project: project)
      create(:service, project: project)

      expect(project.dokku_resource_summary).to include(services: 2, databases: 1)
    end

    it "destroys associated activity_events on destroy" do
      project = create(:project)
      event = create(:activity_event, project: project)
      expect { project.destroy }.to change { ActivityEvent.count }.by(-1)
      expect(ActivityEvent.exists?(event.id)).to be false
    end
  end
end
