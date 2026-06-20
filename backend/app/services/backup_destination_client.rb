class BackupDestinationClient
  def initialize(destination, client: nil, uploader: nil)
    @destination = destination
    @client = client || Aws::S3::Client.new(client_options)
    @uploader = uploader || Aws::S3::FileUploader.new(client: @client)
  end

  def verify!
    key = @destination.object_key("health/#{SecureRandom.uuid}")
    @client.put_object(bucket: @destination.bucket, key: key, body: "raildock")
    @client.head_object(bucket: @destination.bucket, key: key)
    @client.delete_object(bucket: @destination.bucket, key: key)
    @destination.update!(status: "verified", last_verified_at: Time.current, last_error: nil)
    true
  rescue => error
    @destination.update!(status: "failed", last_error: error.message)
    raise
  end

  def upload(path, key)
    @uploader.upload(path, bucket: @destination.bucket, key: key)
  end

  def download(key, path)
    @client.get_object(response_target: path, bucket: @destination.bucket, key: key)
  end

  def delete(key)
    @client.delete_object(bucket: @destination.bucket, key: key)
  end

  private
    def client_options
      options = {
        region: @destination.region,
        access_key_id: @destination.access_key_id,
        secret_access_key: @destination.secret_access_key,
        retry_mode: "standard"
      }
      options[:endpoint] = @destination.endpoint if @destination.endpoint.present?
      options[:force_path_style] = true if @destination.endpoint.present?
      options
    end
end
