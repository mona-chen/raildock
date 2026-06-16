require "open3"
require "shellwords"

class AppUpdateService
  GITHUB_REPO = "mona-chen/raildock"
  GITHUB_API = "https://api.github.com/repos/#{GITHUB_REPO}/releases/latest"

  class << self
    def current_version
      ENV["RAILDOCK_VERSION"].presence || "unknown"
    end

    def check_for_updates
      response = Faraday.get(GITHUB_API, {
        "Accept" => "application/vnd.github+json",
        "User-Agent" => "RailDock/#{current_version}"
      })

      unless response.success?
        Rails.logger.warn "Update check failed: HTTP #{response.status}"
        update_check_failed("HTTP #{response.status}")
        return nil
      end

      data = JSON.parse(response.body)
      latest_tag = data["tag_name"] || data["name"] || ""
      latest_version = latest_tag.delete_prefix("v")
      release_url = data["html_url"] || ""
      published_at = data["published_at"] || data["created_at"] || ""

      result = {
        latest_version: latest_version,
        latest_tag: latest_tag,
        release_url: release_url,
        published_at: published_at,
        current_version: current_version,
        update_available: update_available?(latest_version),
        checked_at: Time.current.iso8601
      }

      SystemSetting.set!("last_update_check", Time.current.iso8601)
      SystemSetting.set!("update_available_version", latest_version)
      SystemSetting.set!("update_available_url", release_url)
      SystemSetting.set!("update_available", result[:update_available] ? "true" : "false")
      SystemSetting.set!("latest_update_published_at", published_at)

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

      {
        current_version: current_version,
        checked_at: last_check,
        update_available: update_available,
        latest_version: available_version,
        release_url: available_url,
        published_at: published_at
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

      if run_update_script
        SystemSetting.set!("update_available", "false")
        { success: true, message: "Update triggered successfully. RailDock will restart." }
      else
        { success: false, error: "Failed to run update script" }
      end
    end

    private

    def update_available?(latest_version)
      current = current_version
      return false if current == "unknown" || current == "latest"
      return false if latest_version.blank?

      current_normalized = normalize_version(current)
      latest_normalized = normalize_version(latest_version)

      begin
        Gem::Version.new(latest_normalized) > Gem::Version.new(current_normalized)
      rescue ArgumentError
        false
      end
    end

    def normalize_version(version)
      version.to_s.strip.sub(/\Av/, "")
    end

    def update_check_failed(message)
      SystemSetting.set!("last_update_check", Time.current.iso8601)
      SystemSetting.set!("update_available", "false")
      SystemSetting.set!("update_check_error", message)
    end

    def run_update_script
      install_dir = ENV["RAILDOCK_INSTALL_DIR"].presence || "/opt/raildock"
      script_path = File.join(install_dir, "install.sh")

      if File.exist?(script_path)
        cmd = "cd #{Shellwords.escape(install_dir)} && ./install.sh update 2>&1"
      elsif system("which docker-compose >/dev/null 2>&1 || which docker >/dev/null 2>&1")
        cmd = "cd #{Shellwords.escape(install_dir)} && docker compose pull -q && docker compose up -d 2>&1"
      else
        Rails.logger.warn "Cannot apply update: no install.sh or docker command found"
        return false
      end

      Rails.logger.info "Running update: #{cmd}"
      output, status = Open3.capture2e(cmd)

      unless status.success?
        Rails.logger.error "Update failed: #{output}"
        return false
      end

      Rails.logger.info "Update completed successfully"
      true
    end
  end
end
