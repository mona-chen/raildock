class MonitoringNotificationJob < ApplicationJob
  queue_as :observability
  self.enqueue_after_transaction_commit = true
  retry_on StandardError, wait: :polynomially_longer, attempts: 3

  def perform(id, phase)
    ApplicationRecord.connection_pool.with_connection do |connection|
      key = "hashtextextended('raildock:email:#{Integer(id)}', 0)"
      return unless connection.select_value("SELECT pg_try_advisory_lock(#{key})")
      begin
        deliver(id, phase)
      ensure
        connection.select_value("SELECT pg_advisory_unlock(#{key})")
      end
    end
  end

  private

  def deliver(id, phase)
    incident = MonitoringIncident.find_by(id: id)
    return unless incident && incident.state == phase && incident.delivery_status != "delivered"
    policy = MonitoringPolicy.for(incident.server.organization)
    return incident.update!(delivery_status: "disabled") unless policy["enabled"] && policy["email"]

    unless (SystemSetting.smtp_enabled && SystemSetting.smtp_address.present?) || ENV["SMTP_ADDRESS"].present?
      incident.update!(delivery_status: "smtp_unconfigured")
      return
    end
    recipients = incident.server.organization&.admins&.pluck(:email) || []
    recipients << incident.server.organization.owner.email if incident.server.organization
    recipients.concat(Array(policy["email_destinations"]))
    recipients = recipients.compact.uniq { |address| address.downcase }
    return incident.update!(delivery_status: "no_recipients") if recipients.empty?

    SmtpService.apply_from_db!
    raise "SMTP unavailable" unless ActionMailer::Base.delivery_method == :smtp

    MonitoringMailer.incident(incident: incident, recipients: recipients).deliver_now
    incident.update!(delivery_status: "delivered", notified_at: Time.current)
  rescue => e
    incident&.update!(delivery_status: "failed")
    raise e
  end
end
