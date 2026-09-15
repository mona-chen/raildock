require "rails_helper"

RSpec.describe ManifestApplyJob, type: :job do
  let(:server) { create(:server) }
  let(:project) { create(:project, server: server, manifest_format: "raildock.json") }
  let(:manifest) do
    JSON.generate(
      "services" => [
        { "name" => "web", "category" => "app", "subtype" => "web", "builder" => "dockerfile" }
      ]
    )
  end

  def apply(content: manifest, result: { success: true, results: [] })
    reconciler = instance_double(ManifestReconciler, diff: nil, apply!: result)
    allow(ManifestReconciler).to receive(:new).and_return(reconciler)
    allow(DokkuEngine).to receive(:new).and_return(instance_double(DokkuEngine, with_session: nil).tap { |engine| allow(engine).to receive(:with_session).and_yield })
    allow(HostEngine).to receive(:new).and_return(instance_double(HostEngine).tap { |engine| allow(engine).to receive(:with_session).and_yield })
    allow(RealtimeBroadcaster).to receive(:project)

    described_class.perform_now(project.id, content)
  end

  it "records a clean apply when the manifest matches what was applied" do
    project.update!(manifest_content: manifest, manifest_drift_detected: false)

    apply

    project.reload
    expect(project.manifest_last_applied_at).to be_present
    expect(project.manifest_drift_detected).to be(false)
  end

  it "keeps drift when the apply withheld removals" do
    project.update!(manifest_content: manifest, manifest_drift_detected: true)

    apply(result: { success: true, results: [], skipped_removals: %w[legacy-worker] })

    expect(project.reload.manifest_drift_detected).to be(true)
  end

  it "keeps drift when the applied content differs from the stored manifest" do
    project.update!(manifest_content: "# a longer manifest the user wrote", manifest_drift_detected: true)

    apply

    expect(project.reload.manifest_drift_detected).to be(true)
  end
end
