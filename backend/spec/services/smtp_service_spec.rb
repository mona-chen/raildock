require "rails_helper"

RSpec.describe SmtpService do
  around do |example|
    original = ActionMailer::Base.delivery_method
    original_settings = ActionMailer::Base.smtp_settings.dup
    example.run
    ActionMailer::Base.delivery_method = original
    ActionMailer::Base.smtp_settings = original_settings
  end

  describe ".apply_from_db!" do
    context "when smtp is enabled and configured" do
      before do
        SystemSetting.set!("smtp_enabled", "true")
        SystemSetting.set!("smtp_address", "smtp.example.com")
        SystemSetting.set!("smtp_port", "587")
        SystemSetting.set!("smtp_username", "user@example.com")
        SystemSetting.set!("smtp_password", "secret")
        SystemSetting.set!("smtp_domain", "example.com")
        SystemSetting.set!("smtp_auth", "login")
        SystemSetting.set!("smtp_starttls", "false")
        SystemSetting.set!("mail_from", "alerts@example.com")
      end

      it "configures ActionMailer with DB settings" do
        SmtpService.apply_from_db!
        expect(ActionMailer::Base.delivery_method).to eq(:smtp)
        expect(ActionMailer::Base.smtp_settings[:address]).to eq("smtp.example.com")
        expect(ActionMailer::Base.smtp_settings[:port]).to eq(587)
        expect(ActionMailer::Base.smtp_settings[:user_name]).to eq("user@example.com")
        expect(ActionMailer::Base.smtp_settings[:password]).to eq("secret")
        expect(ActionMailer::Base.smtp_settings[:domain]).to eq("example.com")
        expect(ActionMailer::Base.smtp_settings[:authentication]).to eq(:login)
        expect(ActionMailer::Base.smtp_settings[:enable_starttls_auto]).to be(false)
        expect(ApplicationMailer.default[:from]).to eq("alerts@example.com")
      end
    end

    context "when smtp is enabled but address is blank" do
      before do
        SystemSetting.set!("smtp_enabled", "true")
      end

      it "falls back to :test delivery" do
        SmtpService.apply_from_db!
        expect(ActionMailer::Base.delivery_method).to eq(:test)
      end
    end

    context "when smtp is not enabled" do
      before do
        SystemSetting.set!("smtp_enabled", "false")
      end

      it "falls back to :test delivery when no env SMTP_ADDRESS" do
        env_backup = ENV["SMTP_ADDRESS"]
        ENV["SMTP_ADDRESS"] = nil
        SmtpService.apply_from_db!
        expect(ActionMailer::Base.delivery_method).to eq(:test)
      ensure
        ENV["SMTP_ADDRESS"] = env_backup
      end

      it "uses env SMTP_ADDRESS when present" do
        env_backup = ENV["SMTP_ADDRESS"]
        ENV["SMTP_ADDRESS"] = "smtp.env.example.com"
        ENV["SMTP_USERNAME"] = "env-user"
        ENV["SMTP_PASSWORD"] = "env-pass"
        SmtpService.apply_from_db!
        expect(ActionMailer::Base.delivery_method).to eq(:smtp)
        expect(ActionMailer::Base.smtp_settings[:address]).to eq("smtp.env.example.com")
        expect(ActionMailer::Base.smtp_settings[:user_name]).to eq("env-user")
        expect(ActionMailer::Base.smtp_settings[:password]).to eq("env-pass")
      ensure
        ENV["SMTP_ADDRESS"] = env_backup
      end
    end
  end

  describe ".configured?" do
    it "returns true when enabled with address" do
      SystemSetting.set!("smtp_enabled", "true")
      SystemSetting.set!("smtp_address", "smtp.example.com")
      expect(SmtpService.configured?).to be(true)
    end

    it "returns false when not enabled" do
      expect(SmtpService.configured?).to be(false)
    end

    it "returns false when address is missing" do
      SystemSetting.set!("smtp_enabled", "true")
      expect(SmtpService.configured?).to be(false)
    end
  end
end
