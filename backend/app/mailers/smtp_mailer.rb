class SmtpMailer < ApplicationMailer
  def test_email(to:)
    mail(to: to, subject: "RailDock SMTP Test — #{Time.current.iso8601}") do |format|
      format.text { render plain: "This is a test email from RailDock.\n\nSent at: #{Time.current.iso8601}\n\nIf you received this, SMTP is working correctly." }
      format.html { render html: <<~HTML.strip }
        <!DOCTYPE html>
        <html><body style="font-family:system-ui,sans-serif;padding:2em;color:#333">
          <h2 style="color:#7C3AED">RailDock SMTP Test</h2>
          <p>This is a test email from RailDock.</p>
          <p><strong>Sent at:</strong> #{Time.current.iso8601}</p>
          <p style="color:#22c55e">✓ SMTP is working correctly.</p>
        </body></html>
      HTML
    end
  end
end