require "rails_helper"
require "tmpdir"
require "open3"

RSpec.describe ManagedStoragePermissions do
  let(:mount) { instance_double(StorageMount, kind_volume?: true, host_path: "demo-data", container_path: "/data") }
  let(:service) { instance_double(Service, dokku_app_name: "demo", storage_mounts: [ mount ]) }
  let(:engine) { instance_double(DokkuEngine) }
  let(:host) { instance_double(HostEngine) }
  let(:image) { "sha256:" + "a" * 64 }
  subject(:repair) { described_class.new(service, engine: engine, host_engine: host).repair }

  before do
    allow(host).to receive(:run).with(a_string_starting_with("docker volume inspect")).and_return(success: false, output: "")
    allow(host).to receive(:run).with(a_string_starting_with("docker image inspect")).and_return(success: true, output: image)
    allow(host).to receive(:run).with(a_string_ending_with("#{image} -u")).and_return(success: true, output: "10001\n")
    allow(host).to receive(:run).with(a_string_ending_with("#{image} -g")).and_return(success: true, output: "10002\n")
    allow(engine).to receive(:run).with("storage:info demo-data --format json").and_return(success: true, output: {
      name: "demo-data", scheduler: "docker-local", host_path: "/var/lib/dokku/data/storage/demo-data"
    }.to_json)
  end

  it "detects the image identity and repairs an empty root-owned managed directory" do
    expect(host).to receive(:run).with(a_string_including('test "$(stat -c %u -- "$target")" = 0', 'test -z "$first"', 'chown -- 10001:10002 "$target"', 'chmod 700')).and_return(success: true, output: "")
    expect(repair).to eq([ "/data" ])
  end

  it "leaves populated or differently owned storage untouched and does not retry" do
    expect(host).to receive(:run).with(a_string_starting_with("set -eu")).and_return(success: false, output: "")
    expect(repair).to eq([])
  end

  [ false, true ].each do |populated|
    it "#{populated ? 'preserves existing data and ownership' : 'initializes empty storage with private app ownership'} on Linux" do
      skip "needs Linux root for filesystem ownership proof" unless RUBY_PLATFORM.include?("linux") && Process.uid.zero?
      Dir.mktmpdir do |parent|
        path = File.join(parent, "demo-data")
        Dir.mkdir(path)
        File.write(File.join(path, "keep"), "existing data") if populated
        allow(engine).to receive(:run).and_return(success: true, output: {
          name: "demo-data", scheduler: "docker-local", host_path: path
        }.to_json)
        allow(host).to receive(:run).with(a_string_starting_with("set -eu")) do |script|
          output, status = Open3.capture2e("sh", "-c", script)
          { success: status.success?, output: output }
        end
        expect(repair).to eq(populated ? [] : [ "/data" ])
        expect(File.stat(path).uid).to eq(populated ? 0 : 10001)
        if populated
          expect(File.read(File.join(path, "keep"))).to eq("existing data")
        else
          expect(File.stat(path).gid).to eq(10002)
          expect(File.stat(path).mode & 0o777).to eq(0o700)
        end
      end
    end
  end

  it "does not inspect or mutate user-provided bind mounts" do
    allow(mount).to receive(:kind_volume?).and_return(false)
    expect(host).not_to receive(:run)
    expect(engine).not_to receive(:run)
    expect(repair).to eq([])
  end

  it "does not take ownership of custom or shared named storage" do
    allow(mount).to receive(:host_path).and_return("shared-data")
    expect(host).not_to receive(:run)
    expect(repair).to eq([])
  end

  it "supports existing Docker volumes when the Dokku storage registry is unavailable" do
    allow(engine).to receive(:run).and_return(success: false, output: "unsupported command")
    allow(host).to receive(:run).with("docker volume inspect demo-data").and_return(success: true, output: [
      { Name: "demo-data", Driver: "local", Mountpoint: "/var/lib/docker/volumes/demo-data/_data" }
    ].to_json)
    expect(host).to receive(:run).with(a_string_starting_with("set -eu")).and_return(success: true, output: "")
    expect(repair).to eq([ "/data" ])
  end

  it "reports skipped recovery without leaking raw command output" do
    allow(engine).to receive(:run).and_return(success: false, output: "private output")
    recovery = described_class.new(service, engine: engine, host_engine: host)
    expect(recovery.repair).to eq([])
    expect(recovery.messages.join).to include("could not resolve")
    expect(recovery.messages.join).not_to include("private output")
  end

  it "does not change storage for root images" do
    allow(host).to receive(:run).with(a_string_ending_with("#{image} -u")).and_return(success: true, output: "0")
    expect(engine).not_to receive(:run)
    expect(repair).to eq([])
  end

  it "rejects registry records pointing outside the managed directory" do
    allow(engine).to receive(:run).and_return(success: true, output: { name: "demo-data", scheduler: "docker-local", host_path: "/etc" }.to_json)
    expect(host).not_to receive(:run).with(a_string_starting_with("set -eu"))
    expect(repair).to eq([])
  end

  it "does not run the app entrypoint or expose backend environment during identity resolution" do
    expect(host).to receive(:run).with(a_string_including("--network none --read-only --cap-drop ALL --security-opt no-new-privileges --entrypoint id").and(a_string_ending_with(" -u"))).and_return(success: false, output: "")
    expect(engine).not_to receive(:run)
    expect(repair).to eq([])
  end
end
