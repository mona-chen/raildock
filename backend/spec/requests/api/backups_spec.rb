require "rails_helper"

RSpec.describe "Service backups", type: :request do
  let(:user) { create(:user) }
  let(:server) { create(:server) }
  let(:project) { create(:project, server: server) }
  let(:service) { create(:service, :database, project: project, subtype: "postgres") }

  around do |example|
    Dir.mktmpdir do |dir|
      @path = File.join(dir, "verified.dump")
      File.binwrite(@path, "verified database dump")
      example.run
    end
  end

  let!(:backup) do
    service.backups.create!(
      status: "completed",
      file_path: @path,
      size: File.size(@path),
      metadata: { "checksum" => Digest::SHA256.file(@path).hexdigest, "verified_at" => Time.current.iso8601 }
    )
  end

  it "downloads an available verified artifact" do
    get "/api/services/#{service.id}/backups/#{backup.id}/download", headers: auth_headers(user)

    expect(response).to have_http_status(:ok)
    expect(response.body).to eq("verified database dump")
  end

  it "restores an available artifact through the datastore adapter" do
    allow_any_instance_of(DokkuEngine).to receive(:datastore_import_from).with(service, @path).and_return(success: true, output: "")

    expect {
      post "/api/services/#{service.id}/backups/#{backup.id}/restore", headers: auth_headers(user)
    }.to change(ActivityEvent, :count).by(1)

    expect(response).to have_http_status(:ok)
  end

  it "deletes the database record and artifact together" do
    expect {
      delete "/api/services/#{service.id}/backups/#{backup.id}", headers: auth_headers(user)
    }.to change(Backup, :count).by(-1)

    expect(response).to have_http_status(:no_content)
    expect(File).not_to exist(@path)
  end

  it "does not download a missing artifact" do
    File.delete(@path)

    get "/api/services/#{service.id}/backups/#{backup.id}/download", headers: auth_headers(user)

    expect(response).to have_http_status(:not_found)
  end

  it "restores a volume snapshot to its original mount" do
    volume_backup = service.backups.create!(status: "completed", backup_kind: "volume", file_path: @path,
      size: File.size(@path), metadata: { "checksum" => Digest::SHA256.file(@path).hexdigest, "host_path" => "uploads-data" })
    allow_any_instance_of(HostEngine).to receive(:volume_import_from).with("uploads-data", @path).and_return(success: true, output: "")

    post "/api/services/#{service.id}/backups/#{volume_backup.id}/restore", headers: auth_headers(user)

    expect(response).to have_http_status(:ok)
  end
end
