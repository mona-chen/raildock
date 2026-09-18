# frozen_string_literal: true

# Thin, dependency-free wrapper around the S3 API for one backup destination.
#
# Backups are only useful if the destination actually holds the bytes, so every
# write is verified with a `head_object` round-trip and transient failures are
# retried with backoff. This works against AWS S3, Cloudflare R2, MinIO, and any
# other S3-compatible endpoint (set `endpoint` + path-style addressing).
class BackupDestinationClient
  RETRY_LIMIT = 5
  RETRYABLE_ERRORS = [
    Aws::S3::Errors::ServiceError,
    Seahorse::Client::NetworkingError,
    Net::OpenTimeout,
    Net::ReadTimeout,
    Timeout::Error,
    Errno::ECONNRESET,
    Errno::EPIPE,
    SocketError
  ].freeze

  DEFAULT_MULTIPART_THRESHOLD = 64 * 1024 * 1024 # 64 MiB
  UPLOAD_THREADS = 4
  HEALTH_KEY_TTL = 1.day

  def initialize(destination, client: nil, uploader: nil)
    @destination = destination
    @client = client || Aws::S3::Client.new(client_options)
    @uploader = uploader
  end

  # Round-trips a small object through the bucket. A destination is only marked
  # verified when it can be written to *and* read back, so a bucket that accepts
  # writes but cannot serve reads (wrong region, bad policy, wrong endpoint) is
  # caught before it is trusted with a backup.
  def verify!
    key = @destination.object_key("health/#{SecureRandom.uuid}")
    body = "raildock"
    begin
      with_retries do
        @client.put_object(
          bucket: @destination.bucket,
          key: key,
          body: body,
          metadata: { "raildock-expires-at" => (Time.current + HEALTH_KEY_TTL).utc.iso8601 }
        )
        head = @client.head_object(bucket: @destination.bucket, key: key)
        unless head.content_length.to_i == body.bytesize
          raise "destination returned #{head.content_length.to_i} bytes for a #{body.bytesize} byte health check object"
        end
      end

      @destination.update!(status: "verified", last_verified_at: Time.current, last_error: nil)
      true
    rescue => error
      record_failure(error)
      raise
    ensure
      # Never leave probe objects behind; ignore cleanup failures so they cannot
      # mask the real verification result.
      begin
        with_retries(limit: 2) { @client.delete_object(bucket: @destination.bucket, key: key) }
      rescue StandardError => cleanup_error
        Rails.logger.warn "BackupDestinationClient: could not remove health key #{key}: #{cleanup_error.message}"
      end
    end
  end

  # Uploads a file and confirms the destination stored every byte.
  #
  # aws-sdk-s3 made the multipart executor an injected dependency: `FileUploader`
  # no longer accepts `thread_count`, and it does not supply an executor itself.
  # Passing `thread_count` now leaks into `put_object` for files below the
  # multipart threshold ("unexpected value at params[:thread_count]"), while a
  # multipart upload without an executor raises on its first part. The pool is
  # built for one upload and shut down afterwards so no process hoards idle
  # threads and nothing has to survive a fork.
  def upload(path, key)
    with_uploader do |uploader|
      with_retries do
        uploader.upload(path, bucket: @destination.bucket, key: key)
        verify_upload!(key, expected_size: File.size(path))
      end
    end
    key
  end

  def with_uploader
    return yield(@uploader) if @uploader

    executor = Concurrent::FixedThreadPool.new(UPLOAD_THREADS)
    begin
      yield Aws::S3::FileUploader.new(client: @client, multipart_threshold: multipart_threshold, executor: executor)
    ensure
      executor.shutdown
    end
  end

  def verify_upload!(key, expected_size:)
    head = with_retries { @client.head_object(bucket: @destination.bucket, key: key) }
    actual = head.content_length.to_i
    if actual != expected_size.to_i
      raise "uploaded object #{key} is #{actual} bytes on the destination, expected #{expected_size}"
    end

    { content_length: actual, etag: head.etag, last_modified: head.last_modified }
  end

  def download(key, path)
    with_retries do
      @client.get_object(response_target: path, bucket: @destination.bucket, key: key)
    end
  end

  def delete(key)
    with_retries { @client.delete_object(bucket: @destination.bucket, key: key) }
  end

  def object_exists?(key)
    @client.head_object(bucket: @destination.bucket, key: key)
    true
  rescue Aws::S3::Errors::NotFound
    false
  end

  private
    def record_failure(error)
      message = error.message.to_s.truncate(500)
      attributes = { status: "failed", last_error: message }

      if @destination.persisted?
        @destination.update_columns(attributes.merge(updated_at: Time.current))
      else
        @destination.assign_attributes(attributes)
        @destination.save(validate: false)
      end
    rescue => record_error
      Rails.logger.error "BackupDestinationClient: could not record verification failure: #{record_error.message}"
    end

    def with_retries(limit: RETRY_LIMIT)
      attempt = 0
      begin
        attempt += 1
        yield
      rescue *RETRYABLE_ERRORS => error
        raise if attempt >= limit
        raise unless retryable?(error)

        sleep([ 0.5 * (2**(attempt - 1)), 8 ].min)
        retry
      end
    end

    def retryable?(error)
      return true unless error.is_a?(Aws::S3::Errors::ServiceError)

      # Credentials and permissions will not fix themselves; do not hammer the
      # endpoint (and do not make a bad key look like a transient blip).
      !error.is_a?(Aws::S3::Errors::InvalidAccessKeyId) &&
        !error.is_a?(Aws::S3::Errors::SignatureDoesNotMatch) &&
        !error.is_a?(Aws::S3::Errors::AccessDenied)
    end

    def multipart_threshold
      ENV.fetch("RAILDOCK_BACKUP_MULTIPART_THRESHOLD_BYTES", DEFAULT_MULTIPART_THRESHOLD).to_i
    end

    def client_options
      options = {
        region: @destination.region.presence || "us-east-1",
        retry_mode: "standard",
        retry_limit: RETRY_LIMIT,
        http_open_timeout: 10,
        http_read_timeout: 300,
        http_idle_timeout: 30
      }
      if @destination.access_key_id.present?
        options[:access_key_id] = @destination.access_key_id
        options[:secret_access_key] = @destination.secret_access_key
      end
      if @destination.endpoint.present?
        options[:endpoint] = @destination.endpoint
        options[:force_path_style] = true
      end
      options
    end
end
