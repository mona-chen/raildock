class ServerPackageUpdateJob < ApplicationJob
  queue_as :maintenance
  limits_concurrency to: 1, key: ->(server_id, *_) { "server-packages:#{server_id}" }, duration: 5.minutes

  def perform(server_id, action, operation_id)
    return unless operation_id.to_s.match?(/\A[a-f0-9]{32}\z/)
    server = Server.find_by(id: server_id)
    return unless server
    action == "start" ? ServerPackageManager.schedule(server, operation_id) : ServerPackageManager.poll(server, operation_id)
  rescue ApplicationController::AuthorizationDenied, ServiceOperationLock::Busy
    raise
  rescue => error
    Rails.logger.warn "Server package maintenance #{server_id}: #{error.class}"
    # An SSH failure after systemd accepted the command does not prove that the
    # host process stopped. Preserve the active operation, allowing status polling.
    ServerPackageManager.fail_operation(server, "Host maintenance status is unavailable. The host operation may still be running.", status: "running") if server
  end
end
