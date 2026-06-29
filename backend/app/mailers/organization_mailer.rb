class OrganizationMailer < ApplicationMailer
  default from: -> { default_from_address }

  def invitation_email(invitation)
    @invitation = invitation
    @organization = invitation.organization
    @invited_by = invitation.invited_by
    @accept_url = accept_url_for(invitation)
    @expires_at = invitation.expires_at

    mail(
      to: @invitation.email,
      subject: "You've been invited to join #{@organization.name} on RailDock"
    )
  end

  private

  def default_from_address
    SystemSetting.mail_from.presence || ENV.fetch("MAIL_FROM", "no-reply@#{ENV.fetch('APP_HOST', 'localhost')}")
  end

  def accept_url_for(invitation)
    base = Rails.application.config.x.app_url.presence ||
      "#{Rails.application.config.action_mailer.default_url_options[:protocol] || 'http'}://" \
        "#{Rails.application.config.action_mailer.default_url_options[:host]}" \
        "#{":#{Rails.application.config.action_mailer.default_url_options[:port]}" if Rails.application.config.action_mailer.default_url_options[:port]}"
    "#{base}/invitations/#{invitation.token}"
  end
end
