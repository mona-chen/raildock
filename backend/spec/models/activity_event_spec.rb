require 'rails_helper'

RSpec.describe ActivityEvent, type: :model do
  describe "validations" do
    it { is_expected.to validate_presence_of(:message) }

    it "is valid with recognized actions" do
      %w[deployed stopped started scaled linked unlinked created destroyed].each do |action|
        expect(build(:activity_event, action: action)).to be_valid
      end
    end

    it "raises ArgumentError with an unrecognized action" do
      expect {
        build(:activity_event, action: "updated")
      }.to raise_error(ArgumentError, "'updated' is not a valid action")
    end
  end

  describe "associations" do
    it { is_expected.to belong_to(:project) }
  end

  describe "enums" do
    it "defines action enum with prefix" do
      expect(described_class.actions.keys).to contain_exactly("deployed", "stopped", "started", "scaled", "linked", "unlinked", "created", "destroyed")
      event = create(:activity_event, action: :deployed)
      expect(event.action_deployed?).to be true
    end
  end

  describe "default_scope" do
    it "orders by created_at descending" do
      project = create(:project)
      old_event = create(:activity_event, project: project, created_at: 2.days.ago)
      new_event = create(:activity_event, project: project, created_at: 1.hour.ago)
      expect(described_class.all).to eq([new_event, old_event])
    end
  end
end
