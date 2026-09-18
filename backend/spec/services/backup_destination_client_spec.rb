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
