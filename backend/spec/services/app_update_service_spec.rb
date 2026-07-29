require "rails_helper"

RSpec.describe AppUpdateService do
  describe ".last_check_result" do
    it "returns cached update info without crashing when servers use ssh_key_ciphertext" do
      create(:server, ssh_key_ciphertext: "encrypted-key")

      result = described_class.last_check_result

      expect(result).to include(
        current_version: described_class.current_version,
        update_available: false,
        can_apply: be(true).or(be(false)),
        apply_strategy: a_string_matching(/\Amanual|ssh_to_local|docker_compose|install_sh\z/)
      )
    end
  end

  describe ".check_for_updates" do
    let(:releases) do
      [
        {
          "tag_name" => "v0.2.0",
          "html_url" => "https://github.com/mona-chen/raildock/releases/v0.2.0",
          "published_at" => "2026-06-01T00:00:00Z",
          "prerelease" => false,
          "draft" => false
        }
      ]
    end

    before do
      stub_const("ENV", ENV.to_h.merge("RAILDOCK_VERSION" => "0.1.0"))
      response = instance_double(Faraday::Response, success?: true, body: releases.to_json)
      allow(Faraday).to receive(:get).and_return(response)
    end

    it "fetches releases and persists an update check result" do
      result = described_class.check_for_updates

      expect(result).to include(
        latest_version: "0.2.0",
        current_version: "0.1.0",
        update_available: true
      )
      expect(SystemSetting.find_by(key: "update_available_version")&.value).to eq("0.2.0")
    end

    it "passes headers, not query params, to GitHub" do
      described_class.check_for_updates

      expect(Faraday).to have_received(:get).with(
        "https://api.github.com/repos/mona-chen/raildock/releases",
        nil,
        a_hash_including("Accept" => "application/vnd.github+json")
      )
    end
  end

  describe ".apply_update" do
    it "uses HostEngine (root) instead of DokkuEngine for ssh_to_local updates" do
      described_class.remove_instance_variable(:@apply_strategy) if described_class.instance_variable_defined?(:@apply_strategy)

      server = create(:server, ssh_key_ciphertext: "encrypted-key")
      host_engine = instance_double(HostEngine, run: { success: true, output: "ok" })
      allow(HostEngine).to receive(:new).with(server).and_return(host_engine)
      allow(described_class).to receive(:check_for_updates).and_return(
        { update_available: true, latest_version: "0.2.0" }
      )

      # Force the container/SSH strategy path
      allow(File).to receive(:exist?).with("/opt/raildock/install.sh").and_return(false)
      allow(File).to receive(:exist?).with("/.dockerenv").and_return(true)
      allow(File).to receive(:exist?).with("/run/.containerenv").and_return(false)
      allow(File).to receive(:read).with("/proc/1/cgroup").and_return("")

      result = described_class.apply_update

      expect(result[:success]).to be(true)
      expect(host_engine).to have_received(:run).with(a_string_including("./install.sh update"))
    end

    it "returns :manual strategy when inside container without local SSH target" do
      described_class.remove_instance_variable(:@apply_strategy) if described_class.instance_variable_defined?(:@apply_strategy)

      # Inside a container but no SSH server configured
      allow(File).to receive(:exist?).with("/.dockerenv").and_return(true)
      allow(File).to receive(:exist?).with("/run/.containerenv").and_return(false)
      allow(File).to receive(:read).with("/proc/1/cgroup").and_return("")
      allow(File).to receive(:exist?).with("/opt/raildock/install.sh").and_return(true)

      # No server with SSH key → local_ssh_target_present? returns false
      strategy = described_class.send(:detect_apply_strategy)

      expect(strategy).to eq(:manual)
    end

    it "prefers :ssh_to_local over :install_sh when inside container with SSH key" do
      described_class.remove_instance_variable(:@apply_strategy) if described_class.instance_variable_defined?(:@apply_strategy)

      create(:server, ssh_key_ciphertext: "encrypted-key")
      allow(File).to receive(:exist?).with("/.dockerenv").and_return(true)
      allow(File).to receive(:exist?).with("/run/.containerenv").and_return(false)
      allow(File).to receive(:read).with("/proc/1/cgroup").and_return("")
      allow(File).to receive(:exist?).with("/opt/raildock/install.sh").and_return(true)

      strategy = described_class.send(:detect_apply_strategy)

      expect(strategy).to eq(:ssh_to_local)
    end
  end
end
