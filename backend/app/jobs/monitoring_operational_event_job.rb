class MonitoringOperationalEventJob < ApplicationJob
  queue_as :observability
  def perform(kind, id)
    record = case kind
    when "deployment" then Deployment.find_by(id: id)
    when "backup" then Backup.find_by(id: id)
    end
    service = record&.service
    server = service&.project&.server
    return unless server&.organization
    policy = MonitoringPolicy.for(server.organization)
    return unless policy["enabled"]

    success = kind == "deployment" ? "succeeded" : "completed"
    return unless [ "failed", success ].include?(record.status)
    signal = "#{kind}_#{service.id}#{kind == 'backup' ? "_#{record.backup_kind}" : ''}"
    MonitoringEvaluator.transition(server, signal, record.status == "failed", "#{kind.capitalize} failure for #{service.name}", policy.merge("window_minutes" => 0), Time.current)
  end
end
