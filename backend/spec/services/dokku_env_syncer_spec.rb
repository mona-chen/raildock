require "rails_helper"

RSpec.describe DokkuEnvSyncer do
  let(:server) { create(:server) }

  describe ".sync" do
    let(:engine) { instance_double(DokkuEngine) }

    before do
      allow(DokkuEngine).to receive(:new).with(server).and_return(engine)
    end

    it "writes the rendered env atomically via run_with_stdin" do
      allow(engine).to receive(:run).and_return({ success: true, output: "OK" })
      captured_stdin = nil
      allow(engine).to receive(:run_with_stdin) do |cmd, stdin|
        captured_stdin = stdin
        { success: true, output: "OK" }
      end

      env = { "URL_VAR" => "https://example.com/path", "JWT" => "abc.def.ghi" }
      described_class.sync(server: server, app_name: "myapp", desired_env: env)

      expect(captured_stdin).to eq(%(URL_VAR='https://example.com/path'\nJWT='abc.def.ghi'\n))
    end

    it "quotes values containing single quotes with double quotes" do
      allow(engine).to receive(:run).and_return({ success: true, output: "OK" })
      captured_stdin = nil
      allow(engine).to receive(:run_with_stdin) do |cmd, stdin|
        captured_stdin = stdin
        { success: true, output: "OK" }
      end

      described_class.sync(server: server, app_name: "x", desired_env: { "Q" => "it's" })
      expect(captured_stdin).to include(%(Q="it's"\n))
    end

    it "aborts with EnvCorruptError when the existing file fails to parse and auto_repair is disabled" do
      # The validate script is the one that runs `source ENV_FILE` directly
      # (no TMP_FILE reference). The write_atomic script sources TMP_FILE.
      allow(engine).to receive(:run) do |cmd|
        if cmd.include?("source '/var/lib/dokku/config/x/ENV'")
          { success: false, output: "bash: parse error" }
        else
          { success: true, output: "OK" }
        end
      end
      allow(engine).to receive(:run_with_stdin).and_return({ success: true, output: "OK" })

      expect {
        described_class.sync(server: server, app_name: "x", desired_env: { "K" => "V" }, auto_repair: false)
      }.to raise_error(DokkuEnvSyncer::EnvCorruptError, /corrupt/)
    end

    it "auto-repairs a corrupt file by rewriting from the canonical state" do
      # Both validate scripts report corrupt (validate-existing fails);
      # the atomic write succeeds.
      allow(engine).to receive(:run).and_return({ success: false, output: "CORRUPT: line 3" })
      allow(engine).to receive(:run_with_stdin).and_return({ success: true, output: "OK" })

      expect(Rails.logger).to receive(:warn).with(/auto-repairing/)

      expect {
        described_class.sync(server: server, app_name: "x", desired_env: { "K" => "V" })
      }.not_to raise_error

      expect(engine).to have_received(:run_with_stdin).once
    end

    it "raises SyncFailedError when auto-repair write itself fails" do
      allow(engine).to receive(:run).and_return({ success: false, output: "CORRUPT: line 3" })
      allow(engine).to receive(:run_with_stdin).and_return(
        { success: false, output: "ERROR: rendered env failed to parse" }
      )

      expect {
        described_class.sync(server: server, app_name: "x", desired_env: { "K" => "V" })
      }.to raise_error(DokkuEnvSyncer::SyncFailedError, /Auto-repair write failed/)
    end

    it "raises SyncFailedError when the atomic write fails on the host" do
      allow(engine).to receive(:run).and_return({ success: true, output: "OK" })
      allow(engine).to receive(:run_with_stdin).and_return(
        { success: false, output: "ERROR: rendered env failed to parse" }
      )

      expect {
        described_class.sync(server: server, app_name: "x", desired_env: { "K" => "V" })
      }.to raise_error(DokkuEnvSyncer::SyncFailedError, /rendered env failed to parse/)
    end

    describe "rendering edge cases" do
      let(:env) { {} }
      let(:instance) { described_class.new(server, "x", env, false, false) }

      it "produces an empty-quoted pair for empty values" do
        expect(instance.send(:shell_quote, "")).to eq("''")
      end

      it "escapes $() and backticks inside double-quoted values (only when value also contains ')" do
        # Single quotes don't need escaping — bash treats content literally.
        # We only switch to double quotes (and need escaping) when the value
        # itself contains a single quote.
        quoted = instance.send(:shell_quote, "it's $(cmd)")
        expect(quoted).to start_with('"')
        expect(quoted).to include('\\$(')
      end

      it "preserves newlines inside single-quoted values (bash handles multiline)" do
        expect(instance.send(:shell_quote, "a\nb")).to eq("'a\nb'")
      end
    end
  end
end
