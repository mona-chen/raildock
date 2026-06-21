class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("MAIL_FROM", "no-reply@localhost")
  layout "mailer"

  after_action :log_delivery_fallback

  private

  # When SMTP isn't configured we still want invitations to be actionable:
  # surface the rendered message (and accept URL) in the application log so
  # the admin can copy it manually.
  def log_delivery_fallback
    return if delivered_via_smtp?
    Rails.logger.info(
      "[Mailer] Delivered #{action_name} to #{message.to.join(', ')} " \
      "via #{message.delivery_method}. Subject: #{message.subject}"
    )
  end

  def delivered_via_smtp?
    message.delivery_method.is_a?(Mail::SMTP)
  end
end
