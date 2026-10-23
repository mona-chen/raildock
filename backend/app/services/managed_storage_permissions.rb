require "json"
require "shellwords"

# Recover newly attached, empty managed storage for non-root Docker images.
# Never recursively chown data, change bind mounts, or take over shared volumes.
class ManagedStoragePermissions
  def initialize(service, engine:, host_engine:)
    @service, @engine, @host = service, engine, host_engine
  end

  def repair
    mounts = @service.storage_mounts.select do |mount|
      mount.kind_volume? && mount.host_path == StorageMount.volume_name_for(@service.dokku_app_name, mount.container_path)
    end
    return [] if mounts.empty?

    image = "dokku/#{@service.dokku_app_name}:latest"
    inspect = @host.run("docker image inspect --format '{{.Id}}' #{quote(image)}")
    return [] unless inspect[:success] && inspect[:output].strip.match?(/\Asha256:[a-f0-9]{64}\z/)
    image = inspect[:output].strip # immutable image for both identity checks
    uid = identity(image, "-u")
    gid = identity(image, "-g")
    return [] unless uid && gid && uid != "0"

    mounts.filter_map do |mount|
      entry = @engine.run("storage:info #{quote(mount.host_path)} --format json")
      next unless entry[:success]
      data = JSON.parse(entry[:output])
      path = data["host_path"]
      next unless data["name"] == mount.host_path && data["scheduler"] == "docker-local"
      next unless path.is_a?(String) && path.start_with?("/") && File.basename(path) == mount.host_path
      result = @host.run(<<~SH)
        set -eu
        target=#{quote(path)}
        test -d "$target" && test ! -L "$target"
        test "$(realpath -- "$target")" = "$target"
        test "$(stat -c %u -- "$target")" = 0
        first=$(find "$target" -mindepth 1 -maxdepth 1 -print -quit)
        test -z "$first"
        chown -- #{uid}:#{gid} "$target"
        chmod 700 -- "$target"
      SH
      mount.container_path if result[:success]
    rescue JSON::ParserError
      nil
    end
  end

  private

  def identity(image, option)
    result = @host.run("timeout 20 docker run --rm --network none --read-only --cap-drop ALL --security-opt no-new-privileges --entrypoint id #{quote(image)} #{option}")
    value = result[:output].to_s.strip
    value if result[:success] && value.match?(/\A[0-9]{1,10}\z/)
  end

  def quote(value)
    Shellwords.escape(value)
  end
end
