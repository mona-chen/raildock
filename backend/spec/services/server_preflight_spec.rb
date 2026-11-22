require "rails_helper"

RSpec.describe ServerPreflight do
  let(:healthy) do
    {
      "os_id" => "ubuntu", "os_version" => "24.04", "os_name" => "Ubuntu 24.04 LTS",
      "arch" => "x86_64", "uid" => "0", "disk_kb" => (40 * 1024 * 1024).to_s,
      "mem_kb" => (4 * 1024 * 1024).to_s, "port_80" => "free", "port_443" => "free", "reach" => "200"
    }
  end
  let(:preflight) { described_class.new(base_url: "https://raildock.example.com") }

  def status_of(key, facts, **opts)
    checker = opts.any? ? described_class.new(base_url: "https://raildock.example.com", **opts) : preflight
    checker.evaluate(facts).find { |c| c[:key] == key }&.fetch(:status)
  end

  it "passes a supported, well-sized host" do
    checks = preflight.evaluate(healthy)
    expect(checks.map { |c| c[:status] }.uniq).to eq([ "pass" ])
    expect(preflight).not_to be_failed
  end

  it "fails an unsupported OS and architecture" do
    expect(status_of("os", healthy.merge("os_id" => "centos", "os_version" => "9", "os_like" => "rhel fedora"))).to eq("fail")
    expect(status_of("arch", healthy.merge("arch" => "armv7l"))).to eq("fail")
  end

  it "warns on an untested Debian-family release" do
    expect(status_of("os", healthy.merge("os_id" => "linuxmint", "os_version" => "21", "os_like" => "ubuntu debian"))).to eq("warn")
  end

  it "grades disk and memory" do
    expect(status_of("disk", healthy.merge("disk_kb" => (2 * 1024 * 1024).to_s))).to eq("fail")
    expect(status_of("disk", healthy.merge("disk_kb" => (10 * 1024 * 1024).to_s))).to eq("warn")
    expect(status_of("memory", healthy.merge("mem_kb" => (256 * 1024).to_s))).to eq("fail")
    expect(status_of("memory", healthy.merge("mem_kb" => (768 * 1024).to_s))).to eq("warn")
  end

  it "warns when 80/443 are taken, unless an external proxy or Dokku already owns them" do
    busy = healthy.merge("port_80" => "used")
    expect(status_of("ports", busy)).to eq("warn")
    expect(status_of("ports", busy, proxy_mode: "external")).to eq("pass")
    expect(status_of("ports", busy.merge("dokku" => "installed"))).to eq("pass")
  end

  it "fails when the host cannot download bootstrap.sh" do
    expect(status_of("bootstrap_reach", healthy.merge("reach" => "000"))).to eq("fail")
    expect(status_of("bootstrap_reach", healthy.merge("reach" => "404"))).to eq("fail")
    expect(status_of("bootstrap_reach", healthy.merge("reach" => "nocurl"))).to eq("fail")
  end

  it "fails a non-root user without passwordless sudo" do
    expect(status_of("sudo", healthy.merge("uid" => "1000", "sudo" => "missing"))).to eq("fail")
    expect(status_of("sudo", healthy.merge("uid" => "1000", "sudo" => "ok"))).to eq("pass")
  end

  it "warns when the control plane address is local or private" do
    %w[http://localhost:8888 http://127.0.0.1 http://192.168.1.10:8888 http://10.0.0.2 http://raildock.local http://[::1]:3000].each do |url|
      expect(described_class.private_url?(url)).to be(true), url
      expect(described_class.new(base_url: url).evaluate(healthy).find { |c| c[:key] == "app_url" }[:status]).to eq("warn")
    end
    expect(described_class.private_url?("https://raildock.example.com")).to be(false)
    expect(described_class.private_url?("http://203.0.113.10:8888")).to be(false)
  end

  it "shell-escapes the bootstrap URL in the remote script" do
    script = described_class.remote_script("https://x.example.com/$(touch /tmp/pwned)")
    expect(script).to include(Shellwords.escape("https://x.example.com/$(touch /tmp/pwned)/bootstrap.sh"))
    expect(script).not_to include(" https://x.example.com/$(touch")
  end

  it "parses only key=value lines from the remote output" do
    facts = preflight.parse("os_id=ubuntu\nnoise line\nreach=200\nBAD KEY=x\n")
    expect(facts).to eq("os_id" => "ubuntu", "reach" => "200")
  end

  it "runs the script over the SSH session" do
    ssh = double("ssh")
    expect(ssh).to receive(:exec!).with(described_class.remote_script("https://raildock.example.com")).and_return(
      healthy.map { |k, v| "#{k}=#{v}" }.join("\n")
    )
    expect(preflight.run(ssh).map { |c| c[:status] }.uniq).to eq([ "pass" ])
  end
end
