require "rails_helper"

RSpec.describe ServiceSettingsSync do
  describe ServiceSettingsSync::CheckedEngine do
    let(:native) { double("Dokku") }
    subject(:checked) { described_class.new(native) }

    it "refuses a failed host command without exposing command output" do
      allow(native).to receive(:proxy_enable).with("app").and_return(success: false, output: "secret")
      expect { checked.proxy_enable("app") }.to raise_error(ServiceSettingsSync::ApplyError, /Settings were saved/)
    end

    it "preserves successful results and keyword arguments" do
      expect(native).to receive(:resource_limit).with("app", "web", memory_swap: "1g").and_return(success: true)
      expect(checked.resource_limit("app", "web", memory_swap: "1g")).to eq(success: true)
    end
  end
end
