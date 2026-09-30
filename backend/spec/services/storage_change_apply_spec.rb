require "rails_helper"

# Regression cover for the storage-mount reconciliation path.
#
# These cover a data-loss bug: apply_storage_change compared manifest
# entries against actual state using mismatched hash shapes, so
# `desired - actual` and `actual - desired` never matched. Every apply
# therefore re-mounted every mount and then unmounted it and deleted the
# row. The unmount command was additionally built by putting the container
# path in the entry-name position, so it could not match an attachment.
RSpec.describe ManifestReconciler do
  let(:server)  { create(:server) }
  let(:project) { create(:project, server: server) }
  let(:service) { create(:service, project: project, dokku_app_name: "myapp") }
  let(:engine)  { instance_double(DokkuEngine) }

  def reconciler
    described_class.new(project, desired_state(services: []))
  end

  def desired_state(services:, links: [])
    ManifestParser::ManifestDesiredState.new(
      services: services,
      links: links,
      format_detected: "raildock.toml"
    )
  end

  def change_to(new_value, old_value)
    double("change", field: :storage, new_value: new_value, old_value: old_value)
  end

  def apply(new_value, old_value)
    reconciler.send(:apply_storage_change, engine, service, change_to(new_value, old_value))
  end

  before do
    allow(engine).to receive(:storage_mount).and_return({ success: true, output: "" })
    allow(engine).to receive(:storage_unmount).and_return({ success: true, output: "" })
    allow(engine).to receive(:config_set).and_return({ success: true, output: "" })
    allow(engine).to receive(:config_unset).and_return({ success: true, output: "" })
  end

  describe "#canonical_storage_mount" do
    subject(:canonical) { reconciler.send(:canonical_storage_mount, mount) }

    context "with a manifest entry that omits kind" do
      let(:mount) { { host: "/var/lib/dokku/data/storage/app-data", container: "/data" } }

      it "infers bind from the absolute host path" do
        expect(canonical).to eq(host: "/var/lib/dokku/data/storage/app-data", container: "/data", kind: "bind")
      end
    end

    context "with a named volume host" do
      let(:mount) { { host: "app-data", container: "/data" } }

      it "infers volume" do
        expect(canonical).to eq(host: "app-data", container: "/data", kind: "volume")
      end
    end

    context "with an unknown kind" do
      let(:mount) { { host: "app-data", container: "/data", kind: "banana" } }

      it "falls back to volume rather than propagating garbage" do
        expect(canonical[:kind]).to eq("volume")
      end
    end

    context "with a string-keyed hash" do
      let(:mount) { { "host" => "app-data", "container" => "/data", "kind" => "volume" } }

      it "normalises it identically to the symbol-keyed form" do
        expect(canonical).to eq({ host: "app-data", container: "/data", kind: "volume" })
      end
    end
  end

  describe "a mount that already exists" do
    let(:desired) { [ { host: "app-data", container: "/data", kind: "volume" } ] }
    let(:actual)  { [ { host: "app-data", container: "/data", kind: "volume" } ] }

    before { service.storage_mounts.create!(host_path: "app-data", container_path: "/data", kind: "volume") }

    it "performs no host operations" do
      apply(desired, actual)

      expect(engine).not_to have_received(:storage_mount)
      expect(engine).not_to have_received(:storage_unmount)
    end

    it "keeps the existing row" do
      expect { apply(desired, actual) }
        .not_to change { service.storage_mounts.count }
    end

    it "reports success" do
      expect(apply(desired, actual)[:success]).to be(true)
    end
  end

  describe "the regression: identical mount expressed with and without kind" do
    # This is the exact shape mismatch that caused the data loss. The
    # manifest side carries `kind`, the old actual-state side did not.
    let(:desired) { [ { host: "app-data", container: "/data", kind: "volume" } ] }
    let(:actual)  { [ { host: "app-data", container: "/data" } ] }

    before { service.storage_mounts.create!(host_path: "app-data", container_path: "/data", kind: "volume") }

    it "treats them as equivalent and does not unmount" do
      apply(desired, actual)

      expect(engine).not_to have_received(:storage_unmount)
    end

    it "does not delete the mount row" do
      expect { apply(desired, actual) }
        .not_to change { service.storage_mounts.count }
    end
  end

  describe "adding a new mount" do
    let(:desired) { [ { host: "app-data", container: "/data", kind: "volume" } ] }
    let(:actual)  { [] }

    it "issues a mount for the host and container from the manifest" do
      apply(desired, actual)

      expect(engine).to have_received(:storage_mount).with("myapp", "app-data", "/data")
    end

    it "persists the row" do
      apply(desired, actual)

      expect(service.storage_mounts.pluck(:host_path, :container_path)).to include([ "app-data", "/data" ])
    end

    it "does not unmount anything" do
      apply(desired, actual)

      expect(engine).not_to have_received(:storage_unmount)
    end
  end

  describe "removing a mount" do
    let(:desired) { [] }
    let(:actual)  { [ { host: "app-data", container: "/data", kind: "volume" } ] }

    before { service.storage_mounts.create!(host_path: "app-data", container_path: "/data", kind: "volume") }

    it "passes the host path in the entry-name position and the container as --container-dir" do
      apply(desired, actual)

      expect(engine).to have_received(:storage_unmount).with("myapp", "app-data", container_path: "/data")
    end

    it "never passes the container path as the entry name" do
      apply(desired, actual)

      expect(engine).to have_received(:storage_unmount) do |_app, entry, _opts|
        expect(entry).not_to eq("/data")
      end
    end

    it "deletes the row" do
      expect { apply(desired, actual) }.to change { service.storage_mounts.count }.by(-1)
    end
  end

  describe "failure handling" do
    let(:desired) { [ { host: "app-data", container: "/data", kind: "volume" } ] }
    let(:actual)  { [] }

    context "when the host rejects the mount" do
      before { allow(engine).to receive(:storage_mount).and_return({ success: false, output: "no such volume" }) }

      it "reports failure rather than claiming success" do
        result = apply(desired, actual)

        expect(result[:success]).to be(false)
        expect(result[:output]).to include("no such volume")
      end

      it "does not create a row for a mount that was not applied" do
        apply(desired, actual)

        expect(service.storage_mounts.count).to eq(0)
      end
    end

    context "when the unmount fails" do
      let(:desired) { [] }
      let(:actual)  { [ { host: "app-data", container: "/data", kind: "volume" } ] }

      before do
        service.storage_mounts.create!(host_path: "app-data", container_path: "/data", kind: "volume")
        allow(engine).to receive(:storage_unmount).and_return({ success: false, output: "not mounted" })
      end

      it "reports failure" do
        expect(apply(desired, actual)[:success]).to be(false)
      end

      it "keeps the row so it is retried next time" do
        apply(desired, actual)

        expect(service.storage_mounts.count).to eq(1)
      end
    end
  end
end
