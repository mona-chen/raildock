require 'rails_helper'

RSpec.describe GitSource, type: :model do
  describe "validations" do
    it "is valid with recognized providers" do
      %w[github gitlab bitbucket gitea].each do |provider|
        expect(build(:git_source, provider: provider)).to be_valid
      end
    end

    it "is invalid with an unrecognized provider" do
      git_source = build(:git_source, provider: "azure")
      expect(git_source).not_to be_valid
      expect(git_source.errors[:provider]).to include("is not included in the list")
    end
  end

  describe "#repos" do
    it "returns an empty array when metadata is nil" do
      git_source = build(:git_source, metadata: nil)
      expect(git_source.repos).to eq([])
    end

    it "returns an empty array when repos key is missing" do
      git_source = build(:git_source, metadata: { "other" => "data" })
      expect(git_source.repos).to eq([])
    end

    it "returns the repos array when present" do
      repos = [{ "name" => "my-repo", "url" => "https://github.com/user/my-repo" }]
      git_source = build(:git_source, metadata: { "repos" => repos })
      expect(git_source.repos).to eq(repos)
    end
  end

  describe "#repos=" do
    it "initializes metadata when nil" do
      git_source = build(:git_source, metadata: nil)
      git_source.repos = ["repo1"]
      expect(git_source.metadata).to eq({ "repos" => ["repo1"] })
    end

    it "sets the repos key on existing metadata" do
      git_source = build(:git_source, metadata: { "other" => "data" })
      git_source.repos = ["repo1"]
      expect(git_source.metadata).to eq({ "other" => "data", "repos" => ["repo1"] })
    end
  end
end
