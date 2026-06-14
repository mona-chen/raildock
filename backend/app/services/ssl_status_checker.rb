# Checks SSL certificate status for domains by probing port 443 via the
# external Traefik network.  Called after deploys and by a periodic background
# job for domains in "pending" state.
class SslStatusChecker
  PENDING_TIMEOUT = 5.minutes

  def initialize(host_engine)
    @host_engine = host_engine
  end

  # Check a single domain and update its ssl_status.
  def check(domain)
    unless domain.ssl
      domain.update!(ssl_status: "none", ssl_status_message: nil, ssl_checked_at: Time.current)
      return
    end

    # Wildcard domains always need DNS challenge — mark as pending until
    # the user configures a DNS provider.
    if domain.wildcard? && domain.challenge_type != "dns"
      domain.update!(
        ssl_status: "failed",
        ssl_status_message: "Wildcard certificates require DNS-01 challenge. Configure a DNS provider in server settings.",
        ssl_checked_at: Time.current
      )
      return
    end

    result = probe_certificate(domain.hostname)

    if result[:success]
      domain.update!(
        ssl_status: "active",
        ssl_status_message: nil,
        ssl_expires_at: result[:expires_at],
        ssl_checked_at: Time.current
      )
    elsif pending_too_long?(domain)
      domain.update!(
        ssl_status: "failed",
        ssl_status_message: diagnose_failure(domain, result),
        ssl_checked_at: Time.current
      )
    else
      domain.update!(
        ssl_status: "pending",
        ssl_status_message: nil,
        ssl_checked_at: Time.current
      )
    end
  end

  # Check all pending domains for a service.
  def check_service(service)
    service.domains.where(ssl: true).each { |d| check(d) }
  end

  private

  attr_reader :host_engine

  def probe_certificate(hostname)
    # Use openssl s_client to check if a valid cert exists.
    # Runs on the host so it can reach Traefik's port 443.
    cmd = "echo | timeout 5 openssl s_client -servername #{Shellwords.escape(hostname)} -connect 127.0.0.1:443 2>/dev/null | openssl x509 -noout -enddate -issuer 2>/dev/null"
    result = host_engine.run(cmd)

    if result[:success] && result[:output].present?
      expires_line = result[:output].match(/notAfter=(.+)/)
      issuer_line = result[:output].match(/issuer=(.+)/)
      {
        success: true,
        expires_at: expires_line ? Time.parse(expires_line[1]) : nil,
        issuer: issuer_line ? issuer_line[1] : nil
      }
    else
      { success: false, output: result[:output] }
    end
  rescue => e
    { success: false, output: e.message }
  end

  def pending_too_long?(domain)
    domain.ssl_checked_at.present? && domain.ssl_checked_at < PENDING_TIMEOUT.ago
  end

  def diagnose_failure(domain, result)
    if domain.magic_domain?
      "SSL is not available for magic domains (#{domain.hostname}). Set ssl=false."
    elsif domain.hostname.include?("sslip.io") || domain.hostname.include?("nip.io")
      "SSL certificates cannot be issued for magic DNS domains."
    elsif result[:output]&.include?("Connection refused")
      "Traefik is not listening on port 443. Check your proxy configuration."
    elsif result[:output]&.include?("timeout") || result[:output]&.include?("Deadline")
      "Connection timed out. The ACME HTTP challenge may be blocked by a redirect or CDN. " \
        "If using Cloudflare, set SSL mode to Flexible or configure DNS challenge in server settings."
    else
      "Certificate not found after #{PENDING_TIMEOUT / 60} minutes. " \
        "The ACME challenge may be failing. Check that port 80 is accessible " \
        "and not redirected to HTTPS. For Cloudflare/CDN domains, use DNS challenge."
    end
  end
end
