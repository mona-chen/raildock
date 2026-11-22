require "rails_helper"

RSpec.describe BackupDestination do
  let(:organization) { create(:organization) }

  def build_destination(overrides = {})
    described_class.new({
      organization: organization,
      name: "S3 #{SecureRandom.hex(3)}",
      provider: "s3",
      bucket: "backups",
      region: "us-east-1"
    }.merge(overrides))
  end

  describe "endpoint validation" do
    it "accepts an http(s) URL with a path" do
      expect(build_destination(endpoint: "https://s3.example.com/backups")).to be_valid
    end

    it "accepts a plain host with a port" do
      expect(build_destination(endpoint: "http://minio:9000")).to be_valid
    end

    it "rejects a non-http scheme" do
      destination = build_destination(endpoint: "ftp://s3.example.com")

      expect(destination).not_to be_valid
      expect(destination.errors[:endpoint]).to include("must be an http(s) URL")
    end

    it "rejects a URL without a host" do
      destination = build_destination(endpoint: "https://")

      expect(destination).not_to be_valid
      expect(destination.errors[:endpoint]).to include("must be an http(s) URL")
    end

    it "rejects credentials, queries and fragments in the endpoint" do
      [
        "https://user:pass@s3.example.com",
        "https://s3.example.com?bucket=other",
        "https://s3.example.com#fragment"
      ].each do |endpoint|
        expect(build_destination(endpoint: endpoint)).not_to be_valid, endpoint
      end
    end

    it "rejects unparseable trailing content" do
      destination = build_destination(endpoint: "https://s3.example.com\n<script>")

      expect(destination).not_to be_valid
      expect(destination.errors[:endpoint]).to include("must be an http(s) URL")
    end
  end
end
