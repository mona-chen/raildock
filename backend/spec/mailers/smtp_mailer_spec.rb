require "rails_helper"

RSpec.describe SmtpMailer, type: :mailer do
  describe "#test_email" do
    let(:mail) { SmtpMailer.test_email(to: "admin@example.com") }

    it "renders the subject" do
      expect(mail.subject).to match("RailDock SMTP Test")
    end

    it "renders the receiver" do
      expect(mail.to).to eq(["admin@example.com"])
    end

    it "renders the sender from default" do
      expect(mail.from).to eq(["no-reply@localhost"])
    end

    it "includes the success indicator in HTML part" do
      expect(mail.html_part.body).to include("SMTP is working correctly")
    end

    it "includes the success indicator in text part" do
      expect(mail.text_part.body).to include("SMTP is working correctly")
    end
  end
end
