class CollectHttpTrafficJob < ApplicationJob
  queue_as :observability
  def perform(server_id)
    server = Server.find_by(id: server_id)
    HttpTrafficCollector.call(server) if server
  end
end
