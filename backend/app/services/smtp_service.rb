class SmtpService
  class << self
    def apply_from_db!
      if SystemSetting.smtp_enabled
        apply_db_settings!
      elsif ENV["SMTP_ADDRESS"].present?
        apply_env_settings!
      else
        ActionMailer::Base.delivery_method = :test
        Rails.logger.info "[SMTP] SMTP not configured; using :test delivery"
      end
    rescue => e
      Rails.logger.error "[SMTP] Failed to apply settings: #{e.message}"
      ActionMailer::Base.delivery_method = :test
    end

    # Applies SMTP settings from ENV["SMTP_ADDRESS"] and related env vars.
    # Safe to call even when the system_settings table does not yet exist.
    def apply_env_settings!
      ActionMailer::Base.delivery_method = :smtp
      ActionMailer::Base.smtp_settings = {
        address: ENV["SMTP_ADDRESS"],
        port: ENV.fetch("SMTP_PORT", 587).to_i,
        user_name: ENV["SMTP_USERNAME"],
        password: ENV["SMTP_PASSWORD"],
        domain: ENV["SMTP_DOMAIN"].presence || ENV.fetch("APP_HOST", "localhost"),
        authentication: ENV.fetch("SMTP_AUTH", "plain").to_sym,
        enable_starttls_auto: ENV.fetch("SMTP_STARTTLS", "true") == "true"
      }

      apply_mail_from!

      Rails.logger.info "[SMTP] Configured from environment → #{ENV["SMTP_ADDRESS"]}:#{ENV.fetch("SMTP_PORT", 587)}"
    end

    def configured?
      SystemSetting.smtp_enabled && SystemSetting.smtp_address.present?
    end

    private

    def apply_db_settings!
      address = SystemSetting.smtp_address
      unless address.present?
        Rails.logger.warn "[SMTP] Marked enabled but smtp_address is blank — falling back to :test"
        ActionMailer::Base.delivery_method = :test
        return
      end

      ActionMailer::Base.delivery_method = :smtp
      ActionMailer::Base.smtp_settings = {
        address: address,
        port: SystemSetting.smtp_port.presence || 587,
        user_name: SystemSetting.smtp_username,
        password: SystemSetting.smtp_password,
        domain: SystemSetting.smtp_domain.presence || ENV.fetch("APP_HOST", "localhost"),
        authentication: (SystemSetting.smtp_auth.presence || :plain).to_sym,
        enable_starttls_auto: SystemSetting.smtp_starttls != "false"
      }

      apply_mail_from!

      Rails.logger.info "[SMTP] Configured from database settings → #{address}:#{SystemSetting.smtp_port || 587}"
    end

    def apply_mail_from!
      from = SystemSetting.mail_from.presence || ENV.fetch("MAIL_FROM", "no-reply@localhost")
      ApplicationMailer.default from: from
    end
  end
end
