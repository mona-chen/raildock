require "rails_helper"
require "tempfile"

RSpec.describe "Service file browser", type: :request do
  let(:user) { create(:user, :admin) }
  let(:organization) { create(:organization, owner: user) }
  let!(:membership) { create(:organization_membership, organization: organization, user: user, role: :owner) }
  let(:server) { create(:server, organization: organization) }
  let(:project) { create(:project, server: server, organization: organization) }
  let(:service) { create(:service, project: project) }
  let(:headers) { { "Authorization" => "Bearer #{user.generate_jwt}", "X-Organization-ID" => organization.id.to_s } }
  let(:browser) { instance_double(AppFileBrowser) }

  before do
    allow(AppFileBrowser).to receive(:new).and_return(browser)
  end

  it "lists files for an app" do
    expect(browser).to receive(:list).with("/app").and_return(
      path: "/app", entries: [ { type: "file", name: "README.md", size: 12 } ], truncated: false,
      process_type: "web", process_types: [ "web" ]
    )

    get "/api/services/#{service.id}/files", params: { path: "/app", process: "web" }, headers: headers

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)["entries"].first["name"]).to eq("README.md")
  end

  it "returns file content" do
    expect(browser).to receive(:preview).with("/app/README.md").and_return(
      path: "/app/README.md", name: "README.md", size: 12, binary: false, too_large: false, content: "Hello world\n"
    )

    get "/api/services/#{service.id}/files/content", params: { path: "/app/README.md" }, headers: headers

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)["content"]).to eq("Hello world\n")
  end

  it "downloads a file as an attachment" do
    expect(browser).to receive(:download).with("/app/README.md").and_return(
      data: "Hello world\n", filename: "README.md", size: 12
    )

    get "/api/services/#{service.id}/files/download", params: { path: "/app/README.md" }, headers: headers

    expect(response).to have_http_status(:ok)
    expect(response.body).to eq("Hello world\n")
    expect(response.headers["Content-Disposition"]).to include("README.md")
  end

  it "uploads a file with update permission" do
    Tempfile.create([ "raildock-upload", ".txt" ]) do |file|
      file.write("hello")
      file.flush
      upload = Rack::Test::UploadedFile.new(file.path, "text/plain", original_filename: "notes.txt")

      expect(browser).to receive(:process_type).and_return("web")
      expect(browser).to receive(:write).with("/app", "notes.txt", kind_of(String), overwrite: false)
        .and_return(path: "/app/notes.txt", name: "notes.txt", size: 5)

      expect {
        post "/api/services/#{service.id}/files", params: { path: "/app", file: upload }, headers: headers
      }.to change(ActivityEvent, :count).by(1)
    end

    expect(response).to have_http_status(:created)
  end

  it "does not allow members to upload" do
    membership.update!(role: :member)
    expect(browser).not_to receive(:write)

    post "/api/services/#{service.id}/files", params: { path: "/app", file: Rack::Test::UploadedFile.new(__FILE__, "text/plain") }, headers: headers

    expect(response).to have_http_status(:forbidden)
  end

  it "rejects datastore services" do
    database = create(:service, :database, project: project)
    get "/api/services/#{database.id}/files", headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JSON.parse(response.body)["code"]).to eq("not_an_app")
  end
end
