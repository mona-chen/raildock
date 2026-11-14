require "rails_helper"
require "open3"

RSpec.describe GitRepositoryPermissions do
  let(:service) { instance_double(Service, dokku_app_name: "inkwell-inkwell") }
  let(:host) { instance_double(HostEngine) }
  subject(:recovery) { described_class.new(service, host_engine: host) }

  it "detects only the object database permission failure" do
    expect(described_class.permission_error?("error: insufficient permission for adding an object to repository database ./objects\nfatal: unpack-objects failed")).to eq(true)
    [ "Authentication failed", "Permission denied (publickey)", "No space left on device", "unpack-objects failed", "Permission denied" ].each do |output|
      expect(described_class.permission_error?(output)).to eq(false)
    end
  end

  it "requires a verified repair marker and reports the scope without exposing host output" do
    expect(host).to receive(:run).with(a_string_including('rev-parse --is-bare-repository', 'flock -n 9', 'objects/info/alternates', 'mountpoint -q', 'find "$objects" -xdev -type d -uid 0 -exec chown --from=0')).and_return(success: true, output: "object_directories_repaired\n")
    expect(recovery.repair).to eq(true)
    expect(recovery.messages.join).to include("repository contents and application storage were left unchanged")
  end

  it "refuses an invalid app name before invoking privileged commands" do
    allow(service).to receive(:dokku_app_name).and_return("../other; touch /tmp/unsafe")
    expect(host).not_to receive(:run)
    expect(recovery.repair).to eq(false)
  end

  %w[unsafe_repository unsafe_objects shared_objects unexpected_owner unsafe_lock deploy_locked already_writable repair_incomplete unexpected_failure].each do |reason|
    it "does not authorize a sync retry after #{reason}" do
      allow(host).to receive(:run).and_return(success: false, output: reason)
      expect(recovery.repair).to eq(false)
      expect(recovery.messages.join).to include("no automatic sync retry")
    end
  end

  it "does not mistake a successful SSH command for a verified repair" do
    allow(Rails.logger).to receive(:warn)
    allow(host).to receive(:run).and_return(success: true, output: "unrelated output")
    expect(recovery.repair).to eq(false)
  end

  it "classifies the reason even when the host appends a diagnostic line after it" do
    allow(host).to receive(:run).and_return(
      success: false,
      output: "unsafe_lock\ngit permission recovery aborted (status=1 line=12)\n"
    )

    expect(recovery.repair).to eq(false)
    expect(recovery.messages.join).to include("deploy-lock directory")
  end

  it "logs the host output when the script aborts without a recognised marker" do
    allow(host).to receive(:run).and_return(
      success: false,
      output: "fatal: not a git repository: '/home/dokku/inkwell-inkwell'\n"
    )
    expect(Rails.logger).to receive(:warn).with(a_string_including("fatal: not a git repository"))

    expect(recovery.repair).to eq(false)
    expect(recovery.messages.join).to include("no automatic sync retry")
    expect(recovery.messages.join).not_to include("fatal: not a git repository")
  end

  it "terminates every exit path with a reason marker instead of relying on errexit" do
    script = nil
    allow(host).to receive(:run) { |command| script = command; { success: true, output: "object_directories_repaired" } }
    recovery.repair

    exits = script.lines.select { |line| line.match?(/\bexit 1\b/) }
    expect(exits).not_to be_empty
    expect(exits).to all(match(/\bfail\(\).*emit "\$1"; exit 1/))
    expect(script).to include("trap '", "emit unexpected_failure", "emit object_directories_repaired")
  end

  it "keeps an aborted repair non-zero so it can never look successful" do
    script = nil
    allow(host).to receive(:run) { |command| script = command; { success: true, output: "object_directories_repaired" } }
    recovery.repair

    out, err, status = Open3.capture3("sh", stdin_data: "#{script.lines.first(5).join}\nfalse\n")

    expect(status.exitstatus).not_to eq(0)
    expect(out).to include("unexpected_failure")
    expect(err).to include("git permission recovery aborted")
  end

  it "generates valid shell and changes only directory metadata" do
    script = nil
    allow(host).to receive(:run) { |command| script = command; { success: true, output: "object_directories_repaired" } }
    recovery.repair
    output, status = Open3.capture2e("sh", "-n", stdin_data: script)
    expect(status.success?).to eq(true), output
    mutations = script.lines.select { |line| line.match?(/-exec (chown|chmod)/) }
    expect(mutations.size).to eq(2)
    expect(mutations).to all(include('find "$objects" -xdev -type d'))
    expect(script).not_to include("chmod -R", "chown -R", "rm -rf")
  end
end
