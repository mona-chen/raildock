require "rails_helper"

RSpec.describe DokkuEngine do
  subject(:engine) { described_class.new(instance_double(Server, ssh_key: "key")) }

  describe "#config_replace_all" do
    it "imports one JSON payload atomically without restarting" do
      expect(engine).to receive(:run_with_stdin).with(
        a_string_including("config:import --replace --no-restart --format json", " -"),
        JSON.generate("PLAIN" => "value", "MULTILINE" => "line one\nline two")
      ).and_return(success: true, output: "")

      expect(engine.config_replace_all("my-app", "PLAIN" => "value", "MULTILINE" => "line one\nline two")[:success]).to be(true)
    end

    it "returns a clear error without clearing config when import fails" do
      allow(engine).to receive(:run_with_stdin).and_return(success: false, output: "invalid json")

      result = engine.config_replace_all("my-app", "KEY" => "value")

      expect(result[:error]).to eq("Atomic config import failed")
    end

    it "clears config without importing a synthetic blank key when no environment exists" do
      expect(engine).to receive(:run).with("config:clear --no-restart my-app").and_return(success: true, output: "")
      expect(engine).not_to receive(:run_with_stdin)

      expect(engine.config_replace_all("my-app", {})[:success]).to be(true)
    end

    it "ignores legacy blank keys instead of sending an invalid Dokku key name" do
      expect(engine).to receive(:run).with("config:clear --no-restart my-app").and_return(success: true, output: "")

      expect(engine.config_replace_all("my-app", "" => "")[:success]).to be(true)
    end
  end
end
