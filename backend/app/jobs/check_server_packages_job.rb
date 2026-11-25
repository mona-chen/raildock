class CheckServerPackagesJob < ApplicationJob
  queue_as :maintenance
  limits_concurrency to: 1, key: "check-server-packages", duration: 30.minutes

  def perform
    Server.connected.find_each do |server|
      operation = server.package_updates["operation"]
      if operation && ServerPackageManager::ACTIVE.include?(operation["status"])
        ServerPackageUpdateJob.perform_later(server.id, "poll", operation["id"])
      elsif server.package_updates["checked_at"].blank? || Time.iso8601(server.package_updates["checked_at"]) < 6.hours.ago
        ServerPackageManager.start(server, "inspect")
      end
    rescue ServerPackageManager::Busy
      next
    end
  end
end
