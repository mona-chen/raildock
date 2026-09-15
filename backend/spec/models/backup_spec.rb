require "rails_helper"

RSpec.describe Backup, type: :model do
  let(:server) { create(:server) }
  let(:project) { create(:project, server: server) }
  let(:service) { create(:service, :database, project: project, subtype: "postgres") }

  describe "#last_copy_for_service?" do
    it "is true for the only completed artifact of a service" do
      backup = service.backups.create!(status: "completed")

      expect(backup.last_copy_for_service?).to be(true)
    end

    it "is false once another completed artifact exists" do
      backup = service.backups.create!(status: "completed")
      service.backups.create!(status: "completed")

      expect(backup.last_copy_for_service?).to be(false)
    end

    it "ignores artifacts that never completed" do
      completed = service.backups.create!(status: "completed")
      service.backups.create!(status: "failed")
      service.backups.create!(status: "pending")

      expect(completed.last_copy_for_service?).to be(true)
    end

    it "is false for a detached artifact, which has no owner to protect" do
      backup = create(:service).backups.create!(status: "completed")
      backup.update_column(:service_id, nil)

      expect(backup.reload.last_copy_for_service?).to be(false)
    end
  end

  describe "#remove_file!" do
    it "refuses to delete the last restore point of a service" do
      backup = service.backups.create!(status: "completed")

      expect { backup.remove_file! }.to raise_error(Backup::LastCopyError, /last completed artifact/)
      expect(Backup.exists?(backup.id)).to be(true)
    end

    it "deletes the artifact once the loss is acknowledged" do
      backup = service.backups.create!(status: "completed")

      expect { backup.remove_file!(force: true) }.to change(Backup, :count).by(-1)
    end

    it "deletes an older artifact without acknowledgement" do
      backup = service.backups.create!(status: "completed")
      newest = service.backups.create!(status: "completed")

      expect { backup.remove_file! }.to change(Backup, :count).by(-1)
      expect(Backup.exists?(newest.id)).to be(true)
    end

    it "deletes a detached artifact without acknowledgement" do
      backup = service.backups.create!(status: "completed")
      backup.update_column(:service_id, nil)

      expect { backup.reload.remove_file! }.to change(Backup, :count).by(-1)
    end
  end

  describe "#remote_verified?" do
    it "is true only when a verified remote copy is recorded" do
      backup = service.backups.create!(status: "completed", metadata: { "remote_verified" => true })
      expect(backup.remote_verified?).to be(true)

      other = service.backups.create!(status: "completed")
      expect(other.remote_verified?).to be(false)
    end
  end

  describe "#source_label" do
    it "keeps the source identity after the service is gone" do
      backup = service.backups.create!(
        status: "completed",
        metadata: { "service_name" => "tween-pay-db", "project_name" => "tween" }
      )
      backup.update_column(:service_id, nil)

      backup.reload
      expect(backup.source_label).to eq("tween / tween-pay-db")
    end
  end
end
