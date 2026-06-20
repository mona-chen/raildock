class BackupArtifactStore
  def persist!(backup, source_path, storage_name: nil)
    checksum = Digest::SHA256.file(source_path).hexdigest
    size = File.size(source_path)
    destination = backup.backup_destination

    if destination
      key = destination.object_key(storage_name || "#{backup.service_id}/#{backup.backup_kind}/#{backup.id}.backup.enc")
      Tempfile.create([ "raildock-encrypted", ".backup" ], binmode: true) do |encrypted|
        BackupArtifactCipher.new.encrypt(source_path, encrypted.path, destination.encryption_key)
        BackupDestinationClient.new(destination).upload(encrypted.path, key)
      end
      backup.update!(status: "completed", file_path: nil, storage_key: key, encrypted: true, size: size,
        metadata: metadata(backup, checksum, destination.name))
      File.delete(source_path) if File.exist?(source_path)
    else
      backup.update!(status: "completed", file_path: source_path, size: size,
        metadata: metadata(backup, checksum, "local"))
    end
    backup
  end

  def materialize(backup)
    if backup.backup_destination
      Tempfile.create([ "raildock-download", ".enc" ], binmode: true) do |encrypted|
        Tempfile.create([ "raildock-plain", ".backup" ], binmode: true) do |plain|
          BackupDestinationClient.new(backup.backup_destination).download(backup.storage_key, encrypted.path)
          BackupArtifactCipher.new.decrypt(encrypted.path, plain.path, backup.backup_destination.encryption_key)
          verify!(backup, plain.path)
          yield plain.path
        end
      end
    else
      verify!(backup, backup.file_path)
      yield backup.file_path
    end
  end

  def remove!(backup)
    BackupDestinationClient.new(backup.backup_destination).delete(backup.storage_key) if backup.backup_destination && backup.storage_key.present?
    File.delete(backup.file_path) if backup.file_path.present? && File.file?(backup.file_path)
  end

  private
    def verify!(backup, path)
      expected = backup.metadata&.fetch("checksum", nil)
      actual = Digest::SHA256.file(path).hexdigest
      raise "Backup checksum verification failed" unless expected.present? && ActiveSupport::SecurityUtils.secure_compare(expected, actual)
    rescue Errno::ENOENT
      raise "Backup artifact is unavailable"
    end

    def metadata(backup, checksum, destination)
      (backup.metadata || {}).merge(
        "checksum" => checksum,
        "verified_at" => Time.current.iso8601,
        "destination" => destination,
        "encryption" => backup.backup_destination ? "AES-256-GCM" : nil
      ).compact
    end
end
