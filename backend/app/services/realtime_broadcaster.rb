class RealtimeBroadcaster
  class << self
    def deployment(service, payload)
      broadcast(DeploymentsChannel, service, payload, "deployment", service.id)
    end

    def project(project, payload)
      broadcast(ProjectChannel, project, payload, "project", project.id)
    end

    def logs(service, payload)
      broadcast(LogsChannel, service, payload, "logs", service.id)
    end

    private
      def broadcast(channel, target, payload, stream, id)
        channel.broadcast_to(target, payload)
        true
      rescue => error
        Rails.logger.warn "Realtime #{stream} broadcast failed for #{id}: #{error.class}: #{error.message}"
        false
      end
  end
end
