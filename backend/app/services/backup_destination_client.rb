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

  # Errors that describe the destination itself (credentials, permissions, a
  # bucket that does not exist, the wrong region or endpoint). Retrying them
  # only delays the answer, so they surface immediately in every mode.
  PERMANENT_ERROR_CODES = %w[
    AccessDenied Forbidden InvalidAccessKeyId SignatureDoesNotMatch
    InvalidToken ExpiredToken TokenRefreshRequired
    NoSuchBucket InvalidBucketName PermanentRedirect MovedPermanently
    AuthorizationHeaderMalformed IllegalLocationConstraintException
    InvalidRequest BadRequest
  ].freeze

  # Interactive verification runs inside an HTTP request (Settings and the
  # service Recovery tab). The health object is eight bytes, so short timeouts
  # and a single extra attempt are plenty; anything slower is reported rather
  # than holding the request open for minutes.
  INTERACTIVE_RETRY_LIMIT = 2
  INTERACTIVE_TIMEOUTS = { http_open_timeout: 5, http_read_timeout: 15, http_idle_timeout: 5 }.freeze

  DEFAULT_MULTIPART_THRESHOLD = 64 * 1024 * 1024 # 64 MiB
  UPLOAD_THREADS = 4
  HEALTH_KEY_TTL = 1.day

  # `interactive: true` is for verification inside a web request: short
  # timeouts, one SDK attempt and at most INTERACTIVE_RETRY_LIMIT attempts of
  # our own. Background uploads keep the patient defaults.
  def initialize(destination, client: nil, uploader: nil, interactive: false)
    @destination = destination
    @interactive = interactive
    @client = client || Aws::S3::Client.new(client_options)
    @uploader = uploader
  end

  # Round-trips a small object through the bucket. A destination is only marked
  # verified when it can be written to *and* read back, so a bucket that accepts
  # writes but cannot serve reads (wrong region, bad policy, wrong endpoint) is
  # caught before it is trusted with a backup.
  #
  # The result is recorded on a persisted destination. An unsaved destination
  # only has its attributes assigned: the caller decides whether to save it, so
  # a failed create never leaves a row behind.
  def verify!
    probe!
    attributes = { status: "verified", last_verified_at: Time.current, last_error: nil }
    if @destination.persisted?
      @destination.update_columns(attributes.merge(updated_at: Time.current))
    else
      @destination.assign_attributes(attributes)
    end
    true
  rescue => error
    record_failure(error)
    raise
  end

  # The write/read/delete round trip without recording anything. Used to test
  # candidate settings (a new destination, or edited credentials) before they
  # replace anything stored.
  def probe!
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
      true
    rescue Aws::S3::Errors::ServiceError => error
      # Exception#message falls back to the class name when the body was empty.
      if error.message.blank? || error.message == error.class.name
        raise error.class.new(error.context, describe_service_error(error))
      end

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
  rescue => error
    # A destination that cannot accept a write is not usable: record it so the
    # recovery UI and DataSafetyReport show the outage instead of the last
    # successful verification, and so PITR's retry backoff has something to act
    # on.
    record_failure(error)
    raise
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
    # Only a stored destination has a status worth recording. An unsaved one is
    # a candidate that failed its probe; persisting it would leave a "failed"
    # row whose recovery key nobody ever saw.
    def record_failure(error)
      message = error.message.to_s.truncate(500)
      attributes = { status: "failed", last_error: message }

      if @destination.persisted?
        @destination.update_columns(attributes.merge(updated_at: Time.current))
      else
        @destination.assign_attributes(attributes)
      end
    rescue => record_error
      Rails.logger.error "BackupDestinationClient: could not record verification failure: #{record_error.message}"
    end

    def with_retries(limit: default_retry_limit)
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

    def default_retry_limit
      @interactive ? INTERACTIVE_RETRY_LIMIT : RETRY_LIMIT
    end

    def retryable?(error)
      return true unless error.is_a?(Aws::S3::Errors::ServiceError)

      # Credentials, permissions, a missing bucket or the wrong region will not
      # fix themselves; do not hammer the endpoint (and do not make a bad key
      # look like a transient blip).
      !PERMANENT_ERROR_CODES.include?(service_error_code(error))
    end

    def service_error_code(error)
      error.code.presence || error.class.name.to_s.demodulize
    end

    # HEAD responses carry no body, so the SDK raises e.g. `Forbidden` with an
    # empty message. Say what that usually means instead of "verification
    # failed: ".
    def describe_service_error(error)
      case service_error_code(error)
      when "Forbidden", "AccessDenied" then "access denied: check the key's permissions on bucket #{@destination.bucket}"
      when "NotFound", "NoSuchBucket" then "bucket #{@destination.bucket} was not found at this endpoint"
      when "BadRequest", "MovedPermanently", "PermanentRedirect" then "the endpoint rejected the request: check the region and endpoint"
      else "#{service_error_code(error)} (HTTP #{error.context&.http_response&.status_code || 'error'})"
      end
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
      if @interactive
        # One SDK attempt (standard mode reads max_attempts; retry_limit is
        # the legacy-mode knob): our own with_retries decides whether to try
        # again.
        options[:retry_limit] = 0
        options[:max_attempts] = 1
        options.merge!(INTERACTIVE_TIMEOUTS)
      end
      if @destination.access_key_id.present?
        options[:access_key_id] = @destination.access_key_id
        options[:secret_access_key] = @destination.secret_access_key
      end

      preset = @destination.provider_preset
      endpoint = @destination.resolved_endpoint
      if endpoint.present?
        options[:endpoint] = endpoint
        options[:force_path_style] = preset[:path_style]
      end
      if preset[:compatible_checksums]
        options[:request_checksum_calculation] = "when_required"
        options[:response_checksum_validation] = "when_required"
      end
      options
    end
end
