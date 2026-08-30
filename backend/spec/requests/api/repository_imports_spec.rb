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
end
