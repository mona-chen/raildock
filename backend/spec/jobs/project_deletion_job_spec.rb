require "rails_helper"

RSpec.describe ProjectDeletionJob, type: :job do
  let!(:project) { create(:project, deletion_status: "queued") }

  before do
    allow(DestructionSnapshot).to receive(:capture_all).and_return(errors: [])
  end

  it "snapshots before destroying and removes the project" do
    allow_any_instance_of(Project).to receive(:destroy_with_resources!).and_wrap_original do |method, **args|
      expect(DestructionSnapshot).to have_received(:capture_all)
      method.call(**args)
    end
    expect { described_class.perform_now(project.id) }.to change(Project, :count).by(-1)
  end

  it "keeps the project and records a recoverable snapshot failure" do
    allow(DestructionSnapshot).to receive(:capture_all).and_return(errors: [ "No verified destination" ])
    described_class.perform_now(project.id)
    expect(project.reload.deletion_status).to eq("failed")
    expect(project.deletion_error_code).to eq("snapshot_required")
    expect(project.deletion_error).to include("No verified destination")
  end

  it "honors explicit data-loss acknowledgement" do
    allow(DestructionSnapshot).to receive(:capture_all).and_return(errors: [ "No verified destination" ])
    expect { described_class.perform_now(project.id, force_destroy_data: true) }.to change(Project, :count).by(-1)
  end

  it "records SSH failures so the project can be retried" do
    allow_any_instance_of(Project).to receive(:destroy_with_resources!).and_raise("SSH timed out")
    described_class.perform_now(project.id)
    expect(project.reload.deletion_status).to eq("failed")
    expect(project.deletion_error).to eq("SSH timed out")
  end

  it "ignores duplicate jobs after deletion" do
    described_class.perform_now(project.id)
    expect { described_class.perform_now(project.id) }.not_to raise_error
  end

  it "runs its own isolated queue and finishes work the queue delayed past the stall window" do
    expect(described_class.new.queue_name).to eq("maintenance")
    project.update!(deletion_requested_at: 3.hours.ago)
    expect { described_class.perform_now(project.id) }.to change(Project, :count).by(-1)
  end
end
