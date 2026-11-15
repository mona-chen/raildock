class ConfigureHttpTrafficJob < ApplicationJob
  queue_as :observability

  def perform(server_id, token)
    server = Server.find(server_id)
    result = HttpTrafficSetup.new(server).apply(token)
    HttpTrafficSetup.new(server).complete(result)
    HttpTrafficCollector.call(server)
  rescue HttpTrafficSetup::Error => e
    server&.with_lock do
      server.update!(traffic_settings: server.traffic_settings.merge("setup_state" => "failed", "setup_error" => e.message))
    end
  end
end
