require "rails_helper"

RSpec.describe Operation, type: :model do
  let(:organization) { create(:organization) }
  let(:project) { create(:project, organization: organization) }
  let(:service) { create(:service, project: project) }

  def operation_for(subject, kind: "deploy", **attributes)
    Operation.create!(
      organization: organization,
      project: project,
      service: service,
      kind: kind,
      subject: subject,
      **attributes
    )
  end

  describe "#status" do
    it "reports a pending deployment as running" do
      deployment = create(:deployment, service: service, status: :pending)

      expect(operation_for(deployment).status).to eq("running")
    end

    it "follows a deployment to its terminal state" do
      deployment = create(:deployment, service: service, status: :succeeded)

      expect(operation_for(deployment).status).to eq("succeeded")

      deployment.update!(status: :failed)
      expect(operation_for(deployment).reload.status).to eq("failed")
    end

    it "reports a waiting manifest operation as running" do
      manifest_operation = ManifestOperation.create!(project: project, status: "waiting")

      expect(operation_for(manifest_operation, kind: "manifest_apply").status).to eq("running")

      manifest_operation.update!(status: "succeeded", completed_at: Time.current)
      expect(operation_for(manifest_operation, kind: "manifest_apply").reload.status).to eq("succeeded")
    end

    it "maps a queued project deletion to pending and a running one to running" do
      project.update!(deletion_status: "queued")
      operation = operation_for(project, kind: "project_deletion")

      expect(operation.status).to eq("pending")

      project.update!(deletion_status: "running")
      expect(operation.status).to eq("running")
    end

    it "falls back to its own status once the subject is gone" do
      project.update!(deletion_status: "running")
      operation = operation_for(project, kind: "project_deletion")
      operation.update_column(:subject_id, 0)

      expect(operation.reload.subject).to be_nil

      operation.update!(status: "succeeded", completed_at: Time.current)
      expect(operation.reload.status).to eq("succeeded")
    end
  end

  describe "idempotency" do
    it "allows one operation per key per organization" do
      Operation.create!(organization: organization, kind: "deploy", idempotency_key: "same-key")

      expect do
        Operation.create!(organization: organization, kind: "deploy", idempotency_key: "same-key")
      end.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "allows the same key in another organization" do
      other = create(:organization)
      Operation.create!(organization: organization, kind: "deploy", idempotency_key: "same-key")

      expect do
        Operation.create!(organization: other, kind: "deploy", idempotency_key: "same-key")
      end.not_to raise_error
    end
  end
end
