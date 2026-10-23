require "json"
require "shellwords"

# Recover newly attached, empty managed storage for non-root Docker images.
# Never recursively chown data, change arbitrary host folders, or take over shared volumes.
class ManagedStoragePermissions
  attr_reader :messages

  def initialize(service, engine:, host_engine:)
    @service, @engine, @host = service, engine, host_engine
    @messages = []
  end

  def repair
    mounts = @service.storage_mounts.select do |mount|
      (mount.kind_volume? && mount.host_path == StorageMount.volume_name_for(@service.dokku_app_name, mount.container_path)) || managed_bind?(mount)
    end
    return skipped("No eligible managed storage found; arbitrary host folders and custom/shared volumes were left unchanged.") if mounts.empty?

    image = "dokku/#{@service.dokku_app_name}:latest"
    inspect = @host.run("docker image inspect --format '{{.Id}}' #{quote(image)}")
    return skipped("Built application image could not be inspected.") unless inspect[:success] && inspect[:output].strip.match?(/\Asha256:[a-f0-9]{64}\z/)
    image = inspect[:output].strip # immutable image for both identity checks
    uid = identity(image, "-u")
    gid = identity(image, "-g")
    return skipped("Application runtime user could not be resolved using id.") unless uid && gid
    return skipped("Application already runs as root; storage ownership was left unchanged.") if uid == "0"

    mounts.filter_map do |mount|
      path = storage_path(mount)
      unless path
        @messages << "#{mount.container_path}: could not resolve its registered storage directory or Docker volume."
        next
      end
      result = @host.run(<<~SH)
        set -eu
        target=#{quote(path)}
        test -d "$target" && test ! -L "$target" || { echo unsafe_directory; exit 1; }
        test "$(realpath -- "$target")" = "$target" || { echo noncanonical_directory; exit 1; }
        test "$(stat -c %u -- "$target")" = 0 || { echo not_root_owned; exit 1; }
        first=$(find "$target" -mindepth 1 -maxdepth 1 -print -quit)
        test -z "$first" || { echo contains_existing_data; exit 1; }
        chown -- #{uid}:#{gid} "$target"
        chmod 700 -- "$target"
      SH
      if result[:success]
        @messages << "#{mount.container_path}: initialized empty storage for the application."
        mount.container_path
      else
        reason = { "not_root_owned" => "directory is not root-owned", "contains_existing_data" => "directory contains existing data", "unsafe_directory" => "directory is missing or is a symlink", "noncanonical_directory" => "directory resolves through a symlink" }[result[:output].to_s.strip] || "host could not safely prepare the directory"
        @messages << "#{mount.container_path}: #{reason}; left unchanged."
        nil
      end
    end
  end

  private

  def skipped(message)
    @messages << message
    []
  end

  def managed_bind?(mount)
    return false unless mount.kind_bind? && mount.host_path.match?(%r{\A/var/lib/dokku/data/storage/[^/]+(?:/[^/]+)*\z})
    path = mount.host_path
    return false unless File.expand_path(path) == path
    # A legacy UI-managed mount can be a host directory. Do not reassign a
    # directory (or its parent/child) registered to another service.
    StorageMount.where.not(service_id: @service.id).pluck(:host_path).none? do |other|
      other == path || other.start_with?(path + "/") || path.start_with?(other + "/")
    end
  end

  def storage_path(mount)
    return mount.host_path if managed_bind?(mount)
    entry = @engine.run("storage:info #{quote(mount.host_path)} --format json")
    if entry[:success]
      data = parse_json(entry[:output])
      data = nil unless data.is_a?(Hash)
      path = data && data["host_path"]
      return path if data && data["name"] == mount.host_path && data["scheduler"] == "docker-local" && path.is_a?(String) && path.start_with?("/") && File.basename(path) == mount.host_path
    end
    # Older hosts may have real Docker volumes rather than Dokku's registry.
    # Inspect an existing volume only: never create a replacement or guess paths.
    volume = @host.run("docker volume inspect #{quote(mount.host_path)}")
    return nil unless volume[:success]
    data = parse_json(volume[:output])
    item = data.is_a?(Array) && data.length == 1 ? data.first : nil
    path = item && item["Mountpoint"]
    path if item && item["Name"] == mount.host_path && item["Driver"] == "local" && path.is_a?(String) && path.start_with?("/") && File.basename(path) == "_data"
  end

  def parse_json(value)
    JSON.parse(value)
  rescue JSON::ParserError
    nil
  end

  def identity(image, option)
    result = @host.run("timeout 20 docker run --rm --network none --read-only --cap-drop ALL --security-opt no-new-privileges --entrypoint id #{quote(image)} #{option}")
    value = result[:output].to_s.strip
    value if result[:success] && value.match?(/\A[0-9]{1,10}\z/)
  end

  def quote(value)
    Shellwords.escape(value)
  end
end
