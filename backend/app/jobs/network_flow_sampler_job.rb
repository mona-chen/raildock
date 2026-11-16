class NetworkFlowSamplerJob < ApplicationJob
  queue_as :observability

  def self.enqueue_once(server_id)
    key = "network-flow-enqueue:#{server_id}"
    return unless Rails.cache.write(key, true, unless_exist: true, expires_in: 10.seconds)
    perform_later(server_id)
  rescue
    Rails.cache.delete(key)
    raise
  end

  def perform(server_id = nil)
    servers = server_id ? Server.where(id: server_id) : Server.all
    servers.find_each do |server|
      NetworkFlowCollector.call(server)
      NetworkFlowCollector.prune(server)
    end
  end
end
