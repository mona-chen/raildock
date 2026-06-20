require "rails_helper"

RSpec.describe LogRedactor do
  describe ".redact" do
    it "removes credentials embedded in clone URLs" do
      input = "Fetching https://x-access-token:ghs_abcdefghijklmnopqrstuvwxyz123456@github.com/acme/app.git"

      output = described_class.redact(input)

      expect(output).to include("https://x-access-token:[REDACTED]@github.com/acme/app.git")
      expect(output).not_to include("ghs_abcdefghijklmnopqrstuvwxyz123456")
    end

    it "removes common token and authorization forms" do
      input = "token=secret-value Authorization: Bearer abc.def.ghi github_pat_abcdefghijklmnopqrstuvwxyz123456"

      output = described_class.redact(input)

      expect(output).to eq("token=[REDACTED] Authorization: Bearer [REDACTED] [REDACTED]")
    end
  end
end
