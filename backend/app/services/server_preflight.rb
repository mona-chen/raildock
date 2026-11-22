require "ipaddr"
require "resolv"
require "shellwords"
require "uri"

# Read-only checks run over the admin SSH session before bootstrap.sh touches
# the host, so an unsupported OS, a full disk or an unreachable control plane
# fails in seconds instead of half-way through a multi-minute Docker/Dokku
# install. Nothing here writes to the host.
#
# Each check is { key:, label:, status: "pass" | "warn" | "fail", detail: }.
# Only "fail" stops provisioning; "warn" is reported and the bootstrap runs.
class ServerPreflight
  SUPPORTED_OS = {
    "ubuntu" => %w[20.04 22.04 24.04 26.04],
    "debian" => %w[11 12 13]
  }.freeze
  SUPPORTED_ARCH = %w[x86_64 amd64 aarch64 arm64].freeze

  MIN_DISK_KB = 5 * 1024 * 1024        # Docker + Dokku + one image
  RECOMMENDED_DISK_KB = 20 * 1024 * 1024
  MIN_MEMORY_KB = 512 * 1024
  RECOMMENDED_MEMORY_KB = 1024 * 1024  # Dokku's documented minimum

  PRIVATE_HOSTNAMES = %w[localhost host.docker.internal].freeze

  attr_reader :checks

  def initialize(base_url:, proxy_mode: "managed")
    @base_url = base_url.to_s
    @proxy_mode = proxy_mode.to_s
    @checks = []
  end

  def self.script_url(base_url)
    "#{base_url.to_s.chomp('/')}/bootstrap.sh"
  end

  # POSIX sh, so it runs under dash on Debian/Ubuntu. Prints `key=value` lines
  # only. The script URL is the only interpolated value and is shell-escaped.
  def self.remote_script(base_url)
    url = Shellwords.escape(script_url(base_url))
    <<~SH
      . /etc/os-release 2>/dev/null; echo "os_id=${ID:-unknown}"; echo "os_version=${VERSION_ID:-unknown}"; echo "os_like=${ID_LIKE:-}"; echo "os_name=${PRETTY_NAME:-unknown}"
      echo "arch=$(uname -m 2>/dev/null)"
      echo "uid=$(id -u 2>/dev/null)"
      if [ "$(id -u)" -ne 0 ]; then if sudo -n true >/dev/null 2>&1; then echo "sudo=ok"; else echo "sudo=missing"; fi; fi
      echo "disk_kb=$(df -Pk / 2>/dev/null | awk 'NR==2 {print $4}')"
      echo "mem_kb=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null)"
      if command -v dokku >/dev/null 2>&1; then echo "dokku=installed"; fi
      for p in 80 443; do
        if command -v ss >/dev/null 2>&1; then
          if ss -Hltn "sport = :$p" 2>/dev/null | grep -q .; then echo "port_$p=used"; else echo "port_$p=free"; fi
        else echo "port_$p=unknown"; fi
      done
      if command -v curl >/dev/null 2>&1; then
        echo "reach=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 -I #{url} 2>/dev/null)"
      else echo "reach=nocurl"; fi
    SH
  end

  # Runs the remote script and evaluates the results.
  def run(ssh)
    output = ssh.exec!(self.class.remote_script(@base_url)).to_s
    evaluate(parse(output))
  end

  def evaluate(facts)
    @checks = []
    check_control_plane_url
    check_os(facts)
    check_arch(facts)
    check_sudo(facts)
    check_disk(facts)
    check_memory(facts)
    check_ports(facts)
    check_reachability(facts)
    @checks
  end

  def failed?
    @checks.any? { |c| c[:status] == "fail" }
  end

  def failures
    @checks.select { |c| c[:status] == "fail" }
  end

  def parse(output)
    output.to_s.each_line.each_with_object({}) do |line, facts|
      key, value = line.chomp.split("=", 2)
      next if value.nil? || key !~ /\A[a-z0-9_]+\z/

      facts[key] = value.strip
    end
  end

  # True when the address is loopback, RFC 1918, link-local, CGNAT or ULA —
  # a remote host on the public internet usually cannot reach it.
  def self.private_url?(base_url)
    host = URI.parse(base_url.to_s).host.to_s.downcase.delete_prefix("[").delete_suffix("]")
    return true if host.blank?
    return true if PRIVATE_HOSTNAMES.include?(host) || host.end_with?(".local", ".localhost", ".internal")

    ip = IPAddr.new(host)
    ip.loopback? || ip.private? || ip.link_local? || IPAddr.new("100.64.0.0/10").include?(ip) || host == "0.0.0.0"
  rescue IPAddr::InvalidAddressError, URI::InvalidURIError
    false
  end

  private

  def add(key, label, status, detail)
    @checks << { key: key, label: label, status: status, detail: detail }
  end

  def check_control_plane_url
    if self.class.private_url?(@base_url)
      add("app_url", "Control plane address", "warn",
          "#{@base_url} is a local or private address. The host downloads bootstrap.sh from it, so it must be on the same network; set APP_URL to a public address otherwise.")
    else
      add("app_url", "Control plane address", "pass", @base_url)
    end
  end

  def check_os(facts)
    id = facts["os_id"].to_s.downcase
    version = facts["os_version"].to_s
    name = facts["os_name"].presence || "#{id} #{version}"

    if SUPPORTED_OS.fetch(id, []).include?(version)
      add("os", "Operating system", "pass", name)
    elsif SUPPORTED_OS.key?(id) || facts["os_like"].to_s.split.any? { |like| SUPPORTED_OS.key?(like) }
      add("os", "Operating system", "warn", "#{name} is not a tested release; Dokku supports Ubuntu 22.04/24.04 and Debian 11+.")
    else
      add("os", "Operating system", "fail", "#{name} is not supported. Dokku requires Ubuntu or Debian.")
    end
  end

  def check_arch(facts)
    arch = facts["arch"].to_s
    if SUPPORTED_ARCH.include?(arch)
      add("arch", "CPU architecture", "pass", arch)
    else
      add("arch", "CPU architecture", "fail", "#{arch.presence || 'unknown'} is not supported (amd64 or arm64 required).")
    end
  end

  def check_sudo(facts)
    return if facts["uid"] == "0" || facts["sudo"].nil?

    if facts["sudo"] == "ok"
      add("sudo", "Root access", "pass", "Passwordless sudo is available")
    else
      add("sudo", "Root access", "fail", "The admin user is not root and cannot run sudo without a password. Use root or allow passwordless sudo.")
    end
  end

  def check_disk(facts)
    kb = Integer(facts["disk_kb"], exception: false)
    return add("disk", "Free disk", "warn", "Free space on / could not be read") unless kb

    detail = "#{format_gb(kb)} free on /"
    status = if kb < MIN_DISK_KB then "fail"
    elsif kb < RECOMMENDED_DISK_KB then "warn"
    else "pass"
    end
    detail += " (at least #{format_gb(MIN_DISK_KB)} required, #{format_gb(RECOMMENDED_DISK_KB)} recommended)" unless status == "pass"
    add("disk", "Free disk", status, detail)
  end

  def check_memory(facts)
    kb = Integer(facts["mem_kb"], exception: false)
    return add("memory", "Memory", "warn", "Total memory could not be read") unless kb

    detail = "#{format_gb(kb)} RAM"
    status = if kb < MIN_MEMORY_KB then "fail"
    elsif kb < RECOMMENDED_MEMORY_KB then "warn"
    else "pass"
    end
    detail += " (Dokku needs 1 GB; add swap or builds may be killed)" unless status == "pass"
    add("memory", "Memory", status, detail)
  end

  # A port that is already bound is a warning, not a failure: it is expected
  # behind an external proxy, and on a host that already runs Dokku it is
  # usually Dokku's own Traefik.
  def check_ports(facts)
    used = %w[80 443].select { |p| facts["port_#{p}"] == "used" }
    unknown = %w[80 443].select { |p| facts["port_#{p}"] == "unknown" }

    if used.empty? && unknown.empty?
      add("ports", "Ports 80/443", "pass", "Free")
    elsif used.empty?
      add("ports", "Ports 80/443", "warn", "Could not check (ss is not installed)")
    elsif @proxy_mode == "external"
      add("ports", "Ports 80/443", "pass", "In use (#{used.join(', ')}) — expected for an external proxy")
    elsif facts["dokku"] == "installed"
      add("ports", "Ports 80/443", "pass", "In use (#{used.join(', ')}) by the existing Dokku installation")
    else
      add("ports", "Ports 80/443", "warn",
          "Port #{used.join(' and ')} is already in use. Dokku's proxy cannot bind it; stop that service or use external proxy mode.")
    end
  end

  def check_reachability(facts)
    url = self.class.script_url(@base_url)
    code = facts["reach"].to_s

    if code == "nocurl"
      add("bootstrap_reach", "Reach bootstrap.sh", "fail", "curl is not installed on the host (apt-get install -y curl).")
    elsif code.match?(/\A[23]\d\d\z/)
      add("bootstrap_reach", "Reach bootstrap.sh", "pass", url)
    else
      reason = code.blank? || code == "000" ? "no response" : "HTTP #{code}"
      add("bootstrap_reach", "Reach bootstrap.sh", "fail", "The host could not download #{url} (#{reason}). Check APP_URL and the firewall between the host and RailDock.")
    end
  end

  def format_gb(kb)
    gb = kb / 1024.0 / 1024.0
    gb >= 10 ? "#{gb.round} GB" : "#{gb.round(1)} GB"
  end
end
