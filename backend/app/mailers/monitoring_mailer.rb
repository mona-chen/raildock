class MonitoringMailer < ApplicationMailer
  def incident(incident:, recipients:)
    mail(to: recipients, subject: "RailDock #{incident.state == 'resolved' ? 'recovery' : 'alert'}: #{incident.server.name}") do |format|
      format.text { render plain: "#{incident.message}\n\nServer: #{incident.server.name}\nObserved: #{incident.last_seen_at.iso8601}\nState: #{incident.state}\n\nOpen RailDock → Settings → Notifications for details and delivery status. Suspicious requests are not proof of a compromise." }
    end
  end
end
