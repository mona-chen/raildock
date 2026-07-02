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
end
