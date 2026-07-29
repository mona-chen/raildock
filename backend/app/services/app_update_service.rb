require "open3"
require "shellwords"

class AppUpdateService
  GITHUB_REPO = "mona-chen/raildock"
  GITHUB_API = "https://api.github.com/repos/#{GITHUB_REPO}/releases"

  class << self
    def current_version
      ENV["RAILDOCK_VERSION"].presence || "unknown"
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
      published = releases.reject { |r| r["draft"] }
      latest = published.first

      if latest.nil?
        Rails.logger.warn "Update check: no published releases found"
        update_check_failed("No published releases")
        return nil
      end

      latest_tag = latest["tag_name"] || latest["name"] || ""
      latest_version = latest_tag.delete_prefix("v")
      release_url = latest["html_url"] || ""
      published_at = latest["published_at"] || latest["created_at"] || ""
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
      published_at = SystemSetting.find_by(key: "latest_update_published_at")&.value
      prerelease = SystemSetting.find_by(key: "latest_update_prerelease")&.value == "true"

      {
        current_version: current_version,
        checked_at: last_check,
        update_available: update_available,
        latest_version: available_version,
        release_url: available_url,
        published_at: published_at,
        prerelease: prerelease,
        can_apply: apply_strategy != :manual,
        apply_strategy: apply_strategy.to_s
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

      case apply_strategy
      when :install_sh
        run_command("./install.sh update")
      when :docker_compose
        run_command("docker compose pull -q && docker compose up -d")
      when :ssh_to_local
        run_ssh_update
      else
        {
          success: false,
          error: "Auto-update is not available in this environment. Run on the host: cd #{ENV['RAILDOCK_INSTALL_DIR'].presence || '/opt/raildock'} && ./install.sh update"
        }
      end
    end

    private

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
        tag = r["tag_name"].to_s.delete_prefix("v")
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
      @apply_strategy ||= detect_apply_strategy
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
      Server.where.not(ssh_key_ciphertext: [ nil, "" ]).exists?
    end

    def run_command(cmd)
      install_dir = ENV["RAILDOCK_INSTALL_DIR"].presence || "/opt/raildock"
      # cmd values are hardcoded at the call sites (./install.sh update,
      # docker compose pull, etc.) but we escape defensively so Brakeman
      # can't flag this as a potential command-injection sink.
      full_cmd = "cd #{Shellwords.escape(install_dir)} && #{Shellwords.escape(cmd)}"
      Rails.logger.info "Running update: #{full_cmd}"
      output, status = Open3.capture2e(full_cmd)

      if status.success?
        SystemSetting.set!("update_available", "false")
        { success: true, message: "Update triggered. RailDock will restart momentarily." }
      else
        Rails.logger.error "Update failed: #{output}"
        { success: false, error: "Update command failed: #{output.lines.last&.strip&.truncate(200) || 'unknown'}" }
      end
    end

    def run_ssh_update
      server = Server.where.not(ssh_key_ciphertext: [ nil, "" ]).order(:id).first
      return { success: false, error: "No SSH key configured" } unless server

      install_dir = ENV["RAILDOCK_INSTALL_DIR"].presence || "/opt/raildock"
      cmd = "cd #{Shellwords.escape(install_dir)} && ./install.sh update 2>&1"
      # HostEngine runs as root, which is what install.sh needs. DokkuEngine
      # connects as the restricted dokku user and cannot run arbitrary shell.
      result = HostEngine.new(server).run(cmd)

      if result[:success]
        SystemSetting.set!("update_available", "false")
        { success: true, message: "Update triggered via SSH. RailDock will restart." }
      else
        { success: false, error: "SSH update failed: #{result[:output].to_s.lines.last&.strip&.truncate(200) || 'unknown'}" }
      end
    end
  end
end
