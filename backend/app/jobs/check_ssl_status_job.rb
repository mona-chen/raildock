# Periodically checks SSL status for domains in "pending" state.
# Scheduled to run every 2 minutes via Solid Queue.
class CheckSslStatusJob < ApplicationJob
  queue_as :default

  def perform
    Domain.where(ssl_status: "pending").find_each do |domain|
      server = domain.service&.project&.server
      next unless server&.ssh_key.present?

      host_engine = HostEngine.new(server)
      SslStatusChecker.new(host_engine).check(domain)
    rescue => e
      Rails.logger.warn "SslStatusChecker failed for domain #{domain.id}: #{e.message}"
    end
  end
end
