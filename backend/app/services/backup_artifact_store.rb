class BackupArtifactStore
  def persist!(backup, source_path, destination_ids: [], storage_name: nil)
    checksum = Digest::SHA256.file(source_path).hexdigest
    size = File.size(source_path)

    destinations = resolve_destinations(backup, destination_ids)

    copies = []
    copies << create_local_copy!(backup, source_path, size, checksum) if keep_local_copy?(destinations, destination_ids)

    destinations.each do |destination|
      copies << upload_to_destination!(backup, source_path, destination, size, checksum, storage_name: storage_name)
    end

    # Refuse to mark a backup complete when nothing was actually written.
    # (Previously a destination id that resolved to no destination, or a
    # remote-only request whose upload silently failed, produced a "completed"
    # backup with no artifact at all.)
    if copies.empty?
      raise "Backup produced no copies (local copy disabled and no destination resolved)"
    end

    backup.update!(
      status: "completed",
      size: size,
      encrypted: copies.any? { |copy| copy.backup_destination.present? },
      metadata: metadata(backup, checksum, copies)
    )

    # When the only copy is remote, remove the local temp file to save disk.
    # Only safe because every remote copy above was verified after upload.
    File.delete(source_path) if copies.none?(&:local?) && File.exist?(source_path)
    backup
  end

  def materialize(backup)
    # Legacy single-copy backups have no BackupCopy rows.
    if backup.backup_copies.empty?
      return materialize_legacy!(backup) { |path| yield path }
    end

    local_copy = backup.backup_copies.find(&:local?)

    if local_copy && backup.file_path.present? && File.file?(backup.file_path)
      verify!(backup, backup.file_path)
      yield backup.file_path
      return
    end

    remote_copy = backup.backup_copies.completed.find { |copy| copy.backup_destination.present? }
    raise "Backup artifact is unavailable" unless remote_copy

    Tempfile.create([ "raildock-download", ".enc" ], binmode: true) do |encrypted|
      Tempfile.create([ "raildock-plain", ".backup" ], binmode: true) do |plain|
        destination = remote_copy.backup_destination
        BackupDestinationClient.new(destination).download(remote_copy.storage_key, encrypted.path)
        BackupArtifactCipher.new.decrypt(encrypted.path, plain.path, destination.encryption_key)
        verify!(backup, plain.path)
        yield plain.path
      end
    end
  end

  def materialize_legacy!(backup)
    if backup.backup_destination.blank?
      verify!(backup, backup.file_path)
      yield backup.file_path
      return
    end

    Tempfile.create([ "raildock-download", ".enc" ], binmode: true) do |encrypted|
      Tempfile.create([ "raildock-plain", ".backup" ], binmode: true) do |plain|
        destination = backup.backup_destination
        BackupDestinationClient.new(destination).download(backup.storage_key, encrypted.path)
        BackupArtifactCipher.new.decrypt(encrypted.path, plain.path, destination.encryption_key)
        verify!(backup, plain.path)
        yield plain.path
      end
    end
  end

  def remove!(backup)
    backup.backup_copies.find_each do |copy|
      if copy.backup_destination.present? && copy.storage_key.present?
        BackupDestinationClient.new(copy.backup_destination).delete(copy.storage_key)
      elsif copy.local? && backup.file_path.present? && File.file?(backup.file_path)
        File.delete(backup.file_path)
      end
      copy.destroy!
    end

    # Legacy single-destination backup handling
    if backup.backup_destination.present? && backup.storage_key.present?
      BackupDestinationClient.new(backup.backup_destination).delete(backup.storage_key)
    end
    File.delete(backup.file_path) if backup.file_path.present? && File.file?(backup.file_path)
  end

  private
    def keep_local_copy?(destinations, requested_ids)
      requested_ids = Array(requested_ids)
      # If no destinations were explicitly requested, keep local by default.
      # Otherwise keep local only if the caller explicitly included nil/"local" in the list.
      requested_ids.empty? || requested_ids.any? { |id| id.nil? || id.to_s == "local" }
    end

    def create_local_copy!(backup, source_path, size, checksum)
      backup.backup_copies.create!(
        kind: :local,
        status: :completed,
        size: size,
        metadata: { "checksum" => checksum }
      ).tap { backup.update!(file_path: source_path) }
    end

    def upload_to_destination!(backup, source_path, destination, size, checksum, storage_name: nil)
      key = destination.object_key(storage_name || default_storage_key(backup))

      verification = Tempfile.create([ "raildock-encrypted", ".backup" ], binmode: true) do |encrypted|
        BackupArtifactCipher.new.encrypt(source_path, encrypted.path, destination.encryption_key)
        # upload verifies the stored object size with head_object, so a partial
        # or rejected upload raises instead of being recorded as a good copy.
        BackupDestinationClient.new(destination).upload(encrypted.path, key)
      end
      remote_size = verification.is_a?(Hash) ? verification[:content_length] : nil

      backup.backup_copies.create!(
        backup_destination: destination,
        kind: destination.provider,
        status: :completed,
        storage_key: key,
        size: size,
        metadata: {
          "checksum" => checksum,
          "encryption" => "AES-256-GCM",
          "verified_at" => Time.current.iso8601,
          "remote_size" => remote_size
        }.compact
      )
    end

    def default_storage_key(backup)
      owner = backup.service_id || backup.id
      "#{owner}/#{backup.backup_kind}/#{backup.id}.backup.enc"
    end

    # Destinations a backup may be written to: the server's own destinations plus
    # its organization's. Explicit ids must resolve, otherwise a scheduled backup
    # would quietly land nowhere.
    def resolve_destinations(backup, destination_ids)
      requested = Array(destination_ids).map { |id| id.to_s.strip }.reject { |id| id.blank? || id == "local" }
      server = backup.service&.project&.server

      destinations = if requested.any?
        scope = BackupDestination.reachable_from(server)
        found = scope.where(id: requested).to_a
        missing = requested - found.map { |destination| destination.id.to_s }
        raise "Unknown backup destination(s): #{missing.join(', ')}" if missing.any?

        found
      else
        []
      end

      destinations = [ backup.backup_destination ] if destinations.empty? && backup.backup_destination
      destinations
    end

    def verify!(backup, path)
      expected = backup.metadata&.fetch("checksum", nil)
      actual = Digest::SHA256.file(path).hexdigest
      raise "Backup checksum verification failed" unless expected.present? && ActiveSupport::SecurityUtils.secure_compare(expected, actual)
    rescue Errno::ENOENT
      raise "Backup artifact is unavailable"
    end

    def metadata(backup, checksum, copies)
      destinations = copies.reject(&:local?).map(&:destination_name).presence
      (backup.metadata || {}).merge(source_metadata(backup)).merge(
        "checksum" => checksum,
        "verified_at" => Time.current.iso8601,
        "destination" => destinations&.join(", ") || "local",
        "encryption" => destinations.present? ? "AES-256-GCM" : nil,
        "copy_count" => copies.size,
        "remote_verified" => copies.any? { |copy| copy.backup_destination.present? && copy.metadata["verified_at"].present? }
      ).compact
    end

    # Snapshot the source identity into the artifact metadata: backup rows
    # outlive the services they came from, so the artifact has to carry the
    # names needed to understand and restore it later.
    def source_metadata(backup)
      service = backup.service
      {
        "service_name" => service&.name,
        "service_subtype" => service&.subtype,
        "project_name" => service&.project&.name,
        "server_name" => service&.project&.server&.name
      }.compact
    end
end
