require "rails_helper"

RSpec.describe BackupDestinationClient do
  let(:server) { create(:server) }
  let(:destination) do
    server.backup_destinations.create!(
      name: "s3", provider: "s3", region: "us-east-1", bucket: "raildock-backups",
      access_key_id: "access", secret_access_key: "secret"
    )
  end
  let(:s3) { instance_double(Aws::S3::Client) }
  let(:uploader) { instance_double(Aws::S3::FileUploader) }
  let(:head) { instance_double(Aws::S3::Types::HeadObjectOutput, content_length: 8, etag: "\"etag\"", last_modified: Time.current) }

  subject(:client) { described_class.new(destination, client: s3, uploader: uploader) }

  before { allow(client).to receive(:sleep) }

  describe "#verify!" do
    it "marks the destination verified after a write, read, and clean-up round trip" do
      expect(s3).to receive(:put_object).with(hash_including(bucket: "raildock-backups", body: "raildock"))
      expect(s3).to receive(:head_object).with(hash_including(bucket: "raildock-backups")).and_return(head)
      expect(s3).to receive(:delete_object).with(hash_including(bucket: "raildock-backups")).once

      expect(client.verify!).to be(true)
      expect(destination.reload).to be_verified
      expect(destination.last_verified_at).to be_present
      expect(destination.last_error).to be_nil
    end

    it "fails when the destination cannot serve back what it accepted" do
      allow(s3).to receive(:put_object)
      allow(s3).to receive(:delete_object)
      allow(s3).to receive(:head_object).and_return(instance_double(Aws::S3::Types::HeadObjectOutput, content_length: 0))

      expect { client.verify! }.to raise_error(/health check object/)

      expect(destination.reload).to be_failed
      expect(destination.last_error).to match(/health check object/)
    end

    it "still removes the probe object when verification fails" do
      allow(s3).to receive(:put_object)
      allow(s3).to receive(:head_object).and_raise(Aws::S3::Errors::AccessDenied.new(nil, "denied"))
      expect(s3).to receive(:delete_object)

      expect { client.verify! }.to raise_error(Aws::S3::Errors::AccessDenied)
    end

    it "retries transient failures before giving up" do
      attempts = 0
      allow(s3).to receive(:put_object) do
        attempts += 1
        raise Aws::S3::Errors::ServiceError.new(nil, "slow down") if attempts < 3
      end
      allow(s3).to receive(:head_object).and_return(head)
      allow(s3).to receive(:delete_object)

      expect(client.verify!).to be(true)
      expect(attempts).to eq(3)
    end

    it "does not retry bad credentials" do
      attempts = 0
      allow(s3).to receive(:put_object) do
        attempts += 1
        raise Aws::S3::Errors::InvalidAccessKeyId.new(nil, "bad key")
      end
      allow(s3).to receive(:delete_object)

      expect { client.verify! }.to raise_error(Aws::S3::Errors::InvalidAccessKeyId)
      expect(attempts).to eq(1)
      expect(destination.reload).to be_failed
    end
  end

  describe "unsaved destinations" do
    let(:candidate) do
      server.backup_destinations.build(
        name: "candidate", provider: "s3", region: "us-east-1", bucket: "raildock-backups",
        access_key_id: "access", secret_access_key: "secret"
      )
    end

    it "never persists a candidate that failed verification" do
      allow(s3).to receive(:put_object).and_raise(Aws::S3::Errors::InvalidAccessKeyId.new(nil, "bad key"))
      allow(s3).to receive(:delete_object)

      expect {
        expect { described_class.new(candidate, client: s3).verify! }.to raise_error(Aws::S3::Errors::InvalidAccessKeyId)
      }.not_to change(BackupDestination, :count)
      expect(candidate).to be_new_record
      expect(candidate.status).to eq("failed")
    end

    it "probes without recording anything on the destination" do
      allow(s3).to receive(:put_object)
      allow(s3).to receive(:head_object).and_return(head)
      allow(s3).to receive(:delete_object)

      expect(described_class.new(candidate, client: s3).probe!).to be(true)
      expect(candidate).to be_new_record
      expect(candidate.status).to eq("pending")
    end
  end

  describe "interactive verification" do
    subject(:interactive) { described_class.new(destination, client: s3, interactive: true) }

    before { allow(interactive).to receive(:sleep) }

    it "gives up after a couple of attempts instead of holding the request" do
      attempts = 0
      allow(s3).to receive(:put_object) do
        attempts += 1
        raise Seahorse::Client::NetworkingError.new(StandardError.new("timeout"))
      end
      allow(s3).to receive(:delete_object)

      expect { interactive.verify! }.to raise_error(Seahorse::Client::NetworkingError)
      expect(attempts).to eq(described_class::INTERACTIVE_RETRY_LIMIT)
    end

    %w[NoSuchBucket InvalidBucketName AuthorizationHeaderMalformed AccessDenied SignatureDoesNotMatch].each do |code|
      it "treats #{code} as permanent" do
        attempts = 0
        allow(s3).to receive(:put_object) do
          attempts += 1
          raise Aws::S3::Errors.error_class(code).new(nil, "nope")
        end
        allow(s3).to receive(:delete_object)

        expect { interactive.verify! }.to raise_error(Aws::S3::Errors::ServiceError)
        expect(attempts).to eq(1)
      end
    end

    it "explains a bodiless 403 instead of an empty message" do
      allow(s3).to receive(:put_object)
      allow(s3).to receive(:head_object).and_raise(Aws::S3::Errors::Forbidden.new(nil, ""))
      allow(s3).to receive(:delete_object)

      expect { interactive.verify! }.to raise_error(/access denied/)
      expect(destination.reload.last_error).to match(/access denied/)
    end

    it "uses short timeouts and a single SDK attempt" do
      options = described_class.new(destination, interactive: true).send(:client_options)

      expect(options).to include(max_attempts: 1, http_open_timeout: 5, http_read_timeout: 15)
    end
  end

  describe "provider presets" do
    def options_for(**attributes)
      record = BackupDestination.new(
        { name: "x", region: "us-east-1", bucket: "b", access_key_id: "a", secret_access_key: "s", server: server }.merge(attributes)
      )
      described_class.new(record, client: s3).send(:client_options)
    end

    it "keeps AWS S3 on the SDK defaults" do
      options = options_for(provider: "s3")
      expect(options).not_to include(:endpoint, :force_path_style, :request_checksum_calculation)
      expect(options).to include(region: "us-east-1", retry_limit: 5, http_read_timeout: 300)
    end

    it "keeps R2 on its configured endpoint with path-style addressing" do
      options = options_for(provider: "r2", region: "auto", endpoint: "https://acct.r2.cloudflarestorage.com")
      expect(options).to include(endpoint: "https://acct.r2.cloudflarestorage.com", force_path_style: true)
      expect(options).not_to include(:request_checksum_calculation)
    end

    {
      "b2" => [ "us-west-004", "https://s3.us-west-004.backblazeb2.com", true ],
      "wasabi" => [ "eu-central-1", "https://s3.eu-central-1.wasabisys.com", true ],
      "spaces" => [ "nyc3", "https://nyc3.digitaloceanspaces.com", false ],
      "hetzner" => [ "fsn1", "https://fsn1.your-objectstorage.com", false ],
      "gcs" => [ "auto", "https://storage.googleapis.com", true ]
    }.each do |provider, (region, endpoint, path_style)|
      it "derives the #{provider} endpoint from the region" do
        options = options_for(provider: provider, region: region)
        expect(options).to include(
          endpoint: endpoint, force_path_style: path_style,
          request_checksum_calculation: "when_required", response_checksum_validation: "when_required"
        )
      end
    end

    it "lets an explicit endpoint override the preset" do
      options = options_for(provider: "b2", region: "us-west-004", endpoint: "https://custom.example.com")
      expect(options).to include(endpoint: "https://custom.example.com")
    end

    it "requires an endpoint for MinIO" do
      record = BackupDestination.new(name: "m", provider: "minio", region: "us-east-1", bucket: "b", server: server)
      expect(record).not_to be_valid
      expect(record.errors[:endpoint]).to be_present
    end
  end

  describe "#upload" do
    around do |example|
      Dir.mktmpdir do |dir|
        @path = File.join(dir, "artifact.enc")
        File.binwrite(@path, "12345")
        example.run
      end
    end

    it "confirms the destination stored the whole object" do
      allow(uploader).to receive(:upload)
      allow(s3).to receive(:head_object).and_return(
        instance_double(Aws::S3::Types::HeadObjectOutput, content_length: 5, etag: "\"etag\"", last_modified: Time.current)
      )

      expect(client.upload(@path, "raildock/k.enc")).to eq("raildock/k.enc")
      # Exactly bucket/key: the SDK forwards every other option to
      # `put_object`, which rejects unknown parameters for files below the
      # multipart threshold ("unexpected value at params[:thread_count]").
      expect(uploader).to have_received(:upload).with(@path, { bucket: "raildock-backups", key: "raildock/k.enc" })
    end

    it "raises when the destination stored fewer bytes than the source" do
      allow(uploader).to receive(:upload)
      allow(s3).to receive(:head_object).and_return(instance_double(Aws::S3::Types::HeadObjectOutput, content_length: 0))

      expect { client.upload(@path, "raildock/k.enc") }.to raise_error(/is 0 bytes on the destination, expected 5/)
    end

    it "gives the SDK uploader a per-upload executor and shuts it down again" do
      executor = nil
      allow(Concurrent::FixedThreadPool).to receive(:new).and_wrap_original do |original, *args|
        executor = original.call(*args)
      end
      allow(s3).to receive(:put_object)
      allow(s3).to receive(:head_object).and_return(
        instance_double(Aws::S3::Types::HeadObjectOutput, content_length: 5, etag: "\"etag\"", last_modified: Time.current)
      )

      expect(Aws::S3::FileUploader).to receive(:new).with(
        client: s3,
        multipart_threshold: described_class::DEFAULT_MULTIPART_THRESHOLD,
        executor: kind_of(Concurrent::FixedThreadPool)
      ).and_call_original

      # No uploader is injected, so the client has to build a real one.
      described_class.new(destination, client: s3).upload(@path, "raildock/k.enc")

      expect(Concurrent::FixedThreadPool).to have_received(:new).with(described_class::UPLOAD_THREADS)
      expect(executor).to be_shutdown
    end
  end

  describe "#object_exists?" do
    it "reports missing objects without raising" do
      allow(s3).to receive(:head_object).and_raise(Aws::S3::Errors::NotFound.new(nil, "missing"))

      expect(client.object_exists?("missing")).to be(false)
    end
  end
end
