require "rails_helper"

RSpec.describe "Repository imports", type: :request do
  let(:user) { create(:user) }
  let(:project) { create(:project, user: user) }
  let(:git_source) do
    create(
      :git_source,
      user: user,
      access_token: nil,
      installation_id: 123,
      metadata: { "repos" => [ { "full_name" => "acme/storefront", "default_branch" => "main" } ] }
    )
  end
  let(:result) do
    RepositoryDiscovery::Result.new(
      repository: "acme/storefront",
      branch: "main",
      commit_sha: "a" * 40,
      services: [
        {
          "name" => "web", "category" => "app", "subtype" => "web", "builder" => "dockerfile",
          "source" => { "type" => "git", "repo" => "https://github.com/acme/storefront.git", "branch" => "main" },
          "env" => {}, "domains" => [], "storage" => [], "proxy" => { "enabled" => true }, "checks" => {}
        }
      ],
      links: [], warnings: [], conflicts: [], evidence: [],
      original_format: "raildock.json", original_content: nil
    )
  end

  before do
    allow(RepositoryDiscovery).to receive(:new).and_return(instance_double(RepositoryDiscovery, call: result))
  end

  it "previews and applies the exact reviewed repository snapshot" do
    post "/api/projects/#{project.id}/repository-import/preview",
      params: { git_source_id: git_source.id, repository: "acme/storefront", branch: "main" },
      headers: auth_headers(user), as: :json

    expect(response).to have_http_status(:ok)
    preview = JSON.parse(response.body)
    expect(preview.dig("services", 0, "builder")).to eq("dockerfile")

    expect {
      post "/api/projects/#{project.id}/repository-import/apply",
        params: { snapshot_token: preview.fetch("snapshot_token"), builder_overrides: { web: "railpack" } },
        headers: auth_headers(user), as: :json
    }.to have_enqueued_job(ManifestApplyJob)

    expect(response).to have_http_status(:accepted)
    expect(project.reload.manifest_content).to include("acme/storefront", '"builder": "railpack"')
  end

  it "does not allow a reviewed snapshot to be replayed into another project" do
    post "/api/projects/#{project.id}/repository-import/preview",
      params: { git_source_id: git_source.id, repository: "acme/storefront" },
      headers: auth_headers(user), as: :json
    token = JSON.parse(response.body).fetch("snapshot_token")
    other_project = create(:project, user: user)

    post "/api/projects/#{other_project.id}/repository-import/apply",
      params: { snapshot_token: token }, headers: auth_headers(user), as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(other_project.reload.manifest_content).to be_blank
  end

  describe "services that the imported manifest omits" do
    let!(:legacy_worker) { create(:service, project: project, name: "legacy-worker", managed_by: :manifest) }

    def preview!
      post "/api/projects/#{project.id}/repository-import/preview",
        params: { git_source_id: git_source.id, repository: "acme/storefront", branch: "main" },
        headers: auth_headers(user), as: :json
      JSON.parse(response.body)
    end

    it "reports them during review" do
      preview = preview!

      expect(preview["removals_require_confirmation"]).to be(true)
      expect(preview["removals"].map { |removal| removal["service_name"] }).to eq([ "legacy-worker" ])
      expect(preview["removal_token"]).to be_present
    end

    it "keeps them when the import does not confirm removals" do
      preview = preview!

      expect {
        post "/api/projects/#{project.id}/repository-import/apply",
          params: { snapshot_token: preview.fetch("snapshot_token") },
          headers: auth_headers(user), as: :json
      }.to have_enqueued_job(ManifestApplyJob).with(project.id, anything, hash_including(allow_removals: false))

      expect(response).to have_http_status(:accepted)
      body = JSON.parse(response.body)
      expect(body["removals_confirmed"]).to be(false)
      expect(body["removals"].map { |removal| removal["service_name"] }).to eq([ "legacy-worker" ])
    end

    it "enables removals once the user confirms the reviewed list" do
      preview = preview!

      expect {
        post "/api/projects/#{project.id}/repository-import/apply",
          params: {
            snapshot_token: preview.fetch("snapshot_token"),
            confirm_removals: true,
            removal_confirmation_token: preview.fetch("removal_token")
          },
          headers: auth_headers(user), as: :json
      }.to have_enqueued_job(ManifestApplyJob).with(project.id, anything, hash_including(allow_removals: true))

      expect(response).to have_http_status(:accepted)
      expect(JSON.parse(response.body)["removals_confirmed"]).to be(true)
    end

    it "does not replace the project's manifest with one that omits them" do
      project.update!(
        manifest_content: "# the seven services this project owns",
        manifest_format: "raildock.json",
        manifest_drift_detected: false
      )
      preview = preview!

      post "/api/projects/#{project.id}/repository-import/apply",
        params: { snapshot_token: preview.fetch("snapshot_token") },
        headers: auth_headers(user), as: :json

      expect(response).to have_http_status(:accepted)
      expect(JSON.parse(response.body)["manifest_adopted"]).to be(false)

      project.reload
      expect(project.manifest_content).to eq("# the seven services this project owns")
      expect(project.manifest_drift_detected).to be(true)
    end

    it "records why the existing manifest was kept" do
      preview = preview!

      post "/api/projects/#{project.id}/repository-import/apply",
        params: { snapshot_token: preview.fetch("snapshot_token") },
        headers: auth_headers(user), as: :json

      warning = ActivityEvent.where(project: project, action: :warning).last
      expect(warning.message).to include("Kept the existing manifest")
      expect(warning.message).to include("legacy-worker")
    end

    it "adopts the manifest once the removals are confirmed" do
      preview = preview!

      post "/api/projects/#{project.id}/repository-import/apply",
        params: {
          snapshot_token: preview.fetch("snapshot_token"),
          confirm_removals: true,
          removal_confirmation_token: preview.fetch("removal_token")
        },
        headers: auth_headers(user), as: :json

      expect(JSON.parse(response.body)["manifest_adopted"]).to be(true)

      project.reload
      expect(project.manifest_content).to include("acme/storefront")
      expect(project.manifest_drift_detected).to be(false)
    end

    it "ignores a confirmation token that does not cover every removal" do
      preview = preview!
      create(:service, project: project, name: "another-worker", managed_by: :manifest)

      expect {
        post "/api/projects/#{project.id}/repository-import/apply",
          params: {
            snapshot_token: preview.fetch("snapshot_token"),
            confirm_removals: true,
            removal_confirmation_token: preview.fetch("removal_token")
          },
          headers: auth_headers(user), as: :json
      }.to have_enqueued_job(ManifestApplyJob).with(project.id, anything, hash_including(allow_removals: false))

      expect(JSON.parse(response.body)["removals_confirmed"]).to be(false)
    end
  end
end
