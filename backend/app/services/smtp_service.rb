class SmtpService
  class << self
    def apply_from_db!
      if SystemSetting.smtp_enabled
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
        Rails.logger.info "[SMTP] Configured from database settings → #{address}:#{SystemSetting.smtp_port || 587}"
      else
        delivery = ENV["SMTP_ADDRESS"].present? ? :smtp : :test
        ActionMailer::Base.delivery_method = delivery
        Rails.logger.info "[SMTP] DB SMTP disabled; using #{delivery}"
      end
    rescue => e
      Rails.logger.error "[SMTP] Failed to apply settings: #{e.message}"
      ActionMailer::Base.delivery_method = :test
    end

    def configured?
      SystemSetting.smtp_enabled && SystemSetting.smtp_address.present?
    end
  end
end