require "rails_helper"

RSpec.describe ProjectResourceTeardown do
  let(:project) { create(:project) }
  let!(:database) { create(:service, :database, project: project, subtype: "mysql") }
  let!(:app) { create(:service, project: project) }
  let(:engine) { instance_double(DokkuEngine) }
  subject(:teardown) { described_class.new(project, engine: engine) }

  it "unlinks owned apps, destroys apps first, then removes the datastore" do
    expect(engine).to receive(:datastore_links).with(database).ordered.and_return(success: true, apps: [ app.dokku_app_name ])
    expect(engine).to receive(:datastore_unlink).with(database, app.dokku_app_name).ordered.and_return(success: true)
    expect(engine).to receive(:app_destroy).with(app.dokku_app_name).ordered.and_return(success: true)
    expect(engine).to receive(:datastore_destroy).with(database).ordered.and_return(success: true)
    expect(teardown.call).to eq([])
  end

  it "refuses before any mutation if an external app still uses a datastore" do
    allow(engine).to receive(:datastore_links).and_return(success: true, apps: [ app.dokku_app_name, "another-project" ])
    expect(engine).not_to receive(:datastore_unlink)
    expect(engine).not_to receive(:app_destroy)
    expect(engine).not_to receive(:datastore_destroy)
    expect(teardown.call.join).to include("outside this project")
  end

  it "preserves datastores when app destruction fails" do
    allow(engine).to receive(:datastore_links).and_return(success: true, apps: [])
    allow(engine).to receive(:app_destroy).and_return(success: false, output: "SSH error")
    expect(engine).not_to receive(:datastore_destroy)
    expect(teardown.call.join).to include("SSH error")
  end

  it "can retry after an earlier attempt already removed the app" do
    allow(engine).to receive(:datastore_links).and_return(success: true, apps: [])
    allow(engine).to receive(:app_destroy).and_return(success: false, output: " ! App #{app.dokku_app_name} does not exist\n")
    expect(engine).to receive(:datastore_destroy).with(database).and_return(success: true)
    expect(teardown.call).to be_empty
  end

  it "does not treat an unverified link read or failed unlink as success" do
    allow(engine).to receive(:datastore_links).and_return(success: false)
    expect(engine).not_to receive(:app_destroy)
    expect(teardown.call.join).to include("could not verify")
  end
end
