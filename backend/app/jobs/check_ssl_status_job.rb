# Refreshes pending certificates and re-checks active certificates every six
# hours so expiry and issuer data do not go stale. Scheduled every two minutes.
class CheckSslStatusJob < ApplicationJob
  queue_as :default
  limits_concurrency to: 1, key: "check-ssl-status", duration: 10.minutes

  def perform
    engines = {}
    Domain.where(ssl: true)
          .where("ssl_status = ? OR ssl_checked_at IS NULL OR ssl_checked_at < ?", "pending", 6.hours.ago)
          .find_each do |domain|
      server = domain.service&.project&.server
      next unless server&.ssh_key.present?

      host_engine = engines[server.id] ||= HostEngine.new(server)
      SslStatusChecker.new(host_engine).check(domain)
    rescue => e
      Rails.logger.warn "SslStatusChecker failed for domain #{domain.id}: #{e.message}"
    end
  end
end
