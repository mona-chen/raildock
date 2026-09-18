require "rails_helper"

RSpec.describe Environment, type: :model do
  describe "default environment" do
    it "creates a production environment when a project is created" do
      project = create(:project)

      expect(project.environments.count).to eq(1)
      expect(project.default_environment.name).to eq("production")
      expect(project.default_environment).to be_default
    end

    it "names the default environment after the project's environment label" do
      project = create(:project, environment: "staging")

      expect(project.environments.pluck(:name)).to eq([ "staging" ])
      expect(project.environments.first).to be_default
    end

    it "refuses a second default environment on the same project" do
      project = create(:project)
      duplicate = project.environments.new(name: "also-default", is_default: true)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:is_default]).to be_present
    end
  end

  describe "slug" do
    it "slugifies the name" do
      project = create(:project)
      environment = project.environments.create!(name: "QA Sandbox")

      expect(environment.slug).to eq("qa-sandbox")
    end

    it "rejects a name that slugifies to nothing" do
      project = create(:project)
      environment = project.environments.new(name: "///")

      expect(environment).not_to be_valid
    end
  end

  describe "ordering" do
    it "lists the default environment first, then creation order" do
      project = create(:project)
      second = project.environments.create!(name: "staging")
      third = project.environments.create!(name: "qa")

      expect(project.environments.ordered.pluck(:name)).to eq(%w[production staging qa])
      expect([ second.slug, third.slug ]).to eq(%w[staging qa])
    end
  end

  describe "destruction guards" do
    it "refuses to delete the default environment" do
      project = create(:project)
      environment = project.default_environment

      expect(environment.destroy).to be(false)
      expect(environment.errors[:base].join).to match(/default environment/)
      expect(project.environments.reload).to include(environment)
    end

    it "refuses to delete an environment that still owns services" do
      project = create(:project)
      staging = project.environments.create!(name: "staging")
      create(:service, project: project, environment: staging)

      expect(staging.destroy).to be(false)
      expect(staging.errors[:base].join).to match(/before deleting it/)
    end

    it "deletes an empty, non-default environment" do
      project = create(:project)
      staging = project.environments.create!(name: "staging")

      expect { staging.destroy! }.to change(Environment, :count).by(-1)
    end
  end

  describe "service assignment" do
    it "assigns a new service to the project's default environment" do
      project = create(:project)
      service = create(:service, project: project)

      expect(service.environment).to eq(project.default_environment)
    end

    it "keeps an explicitly requested environment" do
      project = create(:project)
      staging = project.environments.create!(name: "staging")
      service = create(:service, project: project, environment: staging)

      expect(service.reload.environment).to eq(staging)
    end

    it "rejects an environment from another project" do
      project = create(:project)
      other = create(:project)
      service = build(:service, project: project, environment: other.default_environment)

      expect(service).not_to be_valid
      expect(service.errors[:environment]).to include("must belong to the same project")
    end
  end

  describe "#service_count" do
    it "counts only the services in that environment" do
      project = create(:project)
      staging = project.environments.create!(name: "staging")
      create(:service, project: project)
      create(:service, project: project, environment: staging)
      create(:service, project: project, environment: staging)

      expect(project.default_environment.service_count).to eq(1)
      expect(staging.service_count).to eq(2)
    end
  end
end
