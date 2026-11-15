require "open3"
require "shellwords"

class AppUpdateService
  GITHUB_REPO = "mona-chen/raildock"
  GITHUB_API = "https://api.github.com/repos/#{GITHUB_REPO}/releases"

  class << self
    def current_version
      version = ENV["RAILDOCK_VERSION"].presence || "unknown"
      return File.read(Rails.root.join("BUILD_VERSION")).strip if Rails.root.join("BUILD_VERSION").readable?

      version
    rescue Errno::ENOENT
      version
    end

    def check_for_updates
      response = Faraday.get(GITHUB_API, nil, {
        "Accept" => "application/vnd.github+json",
        "User-Agent" => "RailDock/#{current_version}"
      })

      unless response.success?
        Rails.logger.warn "Update check failed: HTTP #{response.status}"
        update_check_failed("HTTP #{response.status}")
        return nil
      end

      releases = JSON.parse(response.body)
      # /releases/latest excludes prereleases; we want them too since main builds
      # are published as prereleases. Pick the most recent non-draft release.
      published = releases.reject { |r| r["draft"] }.sort_by { |r| r["tag_name"] == "edge" ? r["updated_at"].to_s : (r["published_at"] || r["created_at"]).to_s }.reverse
      # Versioned installations stay on versioned releases; development builds
      # track the rolling edge release without creating a release per commit.
      published = published.reject { |r| r["prerelease"] } if semver?(normalize_version(current_version))
      latest = published.first

      if latest.nil?
        Rails.logger.warn "Update check: no published releases found"
        update_check_failed("No published releases")
        return nil
      end

      latest_tag = latest["tag_name"] || latest["name"] || ""
      latest_version = release_version(latest)
      release_url = latest["html_url"] || ""
      published_at = latest_tag == "edge" ? latest["updated_at"].to_s : (latest["published_at"] || latest["created_at"] || "")
      is_prerelease = !!latest["prerelease"]

      result = {
        latest_version: latest_version,
        latest_tag: latest_tag,
        release_url: release_url,
        published_at: published_at,
        prerelease: is_prerelease,
        current_version: current_version,
        update_available: update_available?(latest_version, published),
        checked_at: Time.current.iso8601
      }

      SystemSetting.set!("update_check_error", "")
      SystemSetting.set!("last_update_check", Time.current.iso8601)
      SystemSetting.set!("update_available_version", latest_version)
      SystemSetting.set!("update_available_url", release_url)
      SystemSetting.set!("update_available", result[:update_available] ? "true" : "false")
      SystemSetting.set!("latest_update_published_at", published_at)
      SystemSetting.set!("latest_update_prerelease", is_prerelease ? "true" : "false")

      result
    rescue Faraday::Error, JSON::ParserError => e
      Rails.logger.warn "Update check error: #{e.message}"
      update_check_failed(e.message)
      nil
    end

    def last_check_result
      last_check = SystemSetting.find_by(key: "last_update_check")&.value
      available_version = SystemSetting.find_by(key: "update_available_version")&.value
      available_url = SystemSetting.find_by(key: "update_available_url")&.value
      update_available = SystemSetting.find_by(key: "update_available")&.value == "true"
      update_available &&= available_version != current_version
      published_at = SystemSetting.find_by(key: "latest_update_published_at")&.value
      prerelease = SystemSetting.find_by(key: "latest_update_prerelease")&.value == "true"

      {
        current_version: current_version,
        check_error: SystemSetting.find_by(key: "update_check_error")&.value.presence,
        checked_at: last_check,
        update_available: update_available,
        latest_version: available_version,
        release_url: available_url,
        published_at: published_at,
        prerelease: prerelease,
        can_apply: apply_strategy != :manual,
        apply_strategy: apply_strategy.to_s,
        operation_status: operation_status&.fetch("status", nil),
        operation_version: SystemSetting.find_by(key: "update_operation_version")&.value
      }
    end

    def auto_update_enabled?
      SystemSetting.find_by(key: "auto_update_enabled")&.value == "true"
    end

    def set_auto_update(enabled)
      SystemSetting.set!("auto_update_enabled", enabled ? "true" : "false")
    end

    def apply_update
      result = check_for_updates
      return { success: false, error: "Update check failed" } unless result
      return { success: false, error: "No update available" } unless result[:update_available]

      target = result[:latest_version]
      return { success: false, error: "An update is already in progress" } if HostUpdateRunner::ACTIVE.include?(operation_status&.fetch("status", nil))

      strategy = apply_strategy
      if strategy == :manual
        return { success: false, error: "No verified local update host is configured. Run ./install.sh update from the installation host." }
      end
      server = strategy == :ssh_to_local ? local_ssh_target : nil
      HostUpdateRunner.new(server: server).schedule(target.to_s)
    end

    def operation_status
      id = SystemSetting.find_by(key: "update_operation_id")&.value
      return nil unless id

      server_id = SystemSetting.find_by(key: "update_operation_server_id")&.value
      server = server_id.present? ? local_ssh_target : nil
      return { "status" => "unavailable" } if server_id.present? && server&.id.to_s != server_id

      HostUpdateRunner.new(server: server).status(id)
    rescue StandardError => error
      Rails.logger.warn("Update status unavailable: #{error.class}")
      { "status" => "unavailable" }
    end

    private

    def release_version(release)
      if release["tag_name"] == "edge"
        release["body"].to_s[/<!-- raildock-version: ([0-9]+\.[0-9]+\.[0-9]+-dev\.[0-9a-f]{8,40}) -->/, 1].to_s
      else
        release["tag_name"].to_s.delete_prefix("v")
      end
    end

    def update_available?(latest_version, releases = [])
      current = current_version
      return false if current == "unknown" || current == "latest"
      return false if latest_version.blank?
      return false if latest_version == current

      current_normalized = normalize_version(current)
      latest_normalized = normalize_version(latest_version)

      # For clean semver (1.2.3), do a real version comparison. Skip the
      # position-based check entirely.
      if semver?(current_normalized) && semver?(latest_normalized)
        return Gem::Version.new(latest_normalized) > Gem::Version.new(current_normalized)
      end

      # For non-semver (e.g. 0.0.0-main-<sha>), compare by position in the
      # chronologically ordered release list. Gem::Version mis-compares these
      # because it interprets the SHA portion as nested pre-release identifiers.
      current_index = releases.find_index do |r|
        tag = release_version(r)
        tag == current || tag == current_normalized
      end

      return true if current_index.nil?
      return false if current_index.zero?

      true
    end

    def semver?(version)
      # Reject strings with prerelease markers like "0.0.0-main-abc123" — those
      # parse as valid Gem::Version but compare unpredictably.
      Gem::Version.correct?(version) && !version.include?("-")
    end

    def normalize_version(version)
      version.to_s.strip.sub(/\Av/, "")
    end

    def update_check_failed(message)
      SystemSetting.set!("last_update_check", Time.current.iso8601)
      SystemSetting.set!("update_available", "false")
      SystemSetting.set!("update_check_error", message)
    end

    # Determines how the running process can apply an update. In priority order:
    #   :install_sh    — local install.sh is on disk (dev / bare-metal install)
    #   :docker_compose — `docker compose` is on PATH and install dir is mounted
    #   :ssh_to_local  — we're inside a container but have an SSH key + local server
    #   :manual        — none of the above; user must run the command themselves
    def apply_strategy
      detect_apply_strategy
    end

    def detect_apply_strategy
      install_dir = ENV["RAILDOCK_INSTALL_DIR"].presence || "/opt/raildock"
      script_path = File.join(install_dir, "install.sh")

      # Inside a container: prefer SSH to the host over install.sh or docker compose,
      # both of which would kill the running container mid-update and leave the new
      # container stuck in Created state.
      if running_in_container?
        return :ssh_to_local if local_ssh_target_present?

        # No SSH key to the host — fall through to manual; never use :install_sh or
        # :docker_compose from inside the container.
        Rails.logger.warn "Auto-update blocked: running inside container with no local SSH target configured."
        return :manual
      end

      return :install_sh if File.exist?(script_path)

      # docker compose must exist and install dir must be reachable
      if docker_compose_available? && Dir.exist?(install_dir)
        return :docker_compose
      end

      :manual
    end

    def docker_compose_available?
      system("which docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1")
    end

    def running_in_container?
      return true if File.exist?("/.dockerenv")
      return true if File.exist?("/run/.containerenv")

      # Podman / others write to /proc/1/cgroup
      return true if File.exist?("/proc/1/cgroup") &&
                     File.read("/proc/1/cgroup").to_s.match?(/docker|containerd|podman|kubepods/)

      false
    end

    def local_ssh_target_present?
      local_ssh_target.present?
    end

    def local_ssh_target
      hosts = ENV["DOKKU_HOST"].present? ? [ ENV["DOKKU_HOST"] ] : %w[host.docker.internal localhost 127.0.0.1 172.17.0.1]
      Server.where(host: hosts).where.not(ssh_key_ciphertext: [ nil, "" ]).order(:id).first
    end
  end
end
