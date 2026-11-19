module Api
  module V1
    # Agent-facing service shape. Values are never serialized: environment
    # variables, config and the webhook token are credentials, so callers get
    # names and "is set" flags instead. The dashboard serializer is deliberately
    # not reused here.
    class ServicePresenter
      def initialize(service)
        @service = service
      end

      def summary
        {
          id: id,
          name: service.name,
          service_type: service.service_type,
          subtype: service.subtype,
          status: service.status,
          environment_id: service.environment_id&.to_s,
          exposed: !!service.exposed,
          domains: service.domains.map(&:hostname),
          last_deployed: service.last_deployed
        }
      end

      def as_json
        summary.merge(
          project_id: service.project_id.to_s,
          created_at: service.created_at&.iso8601,
          port: {
            configured: service.port,
            detected: service.detected_port,
            effective: service.effective_port
          },
          internal_hostname: service.internal_hostname,
          domains: service.domains.map { |domain| domain(domain) },
          storage_mounts: service.storage_mounts.map do |mount|
            { id: mount.id.to_s, container_path: mount.container_path, kind: mount.kind }
          end,
          process_types: service.process_types.map do |process_type|
            {
              name: process_type.name,
              quantity: process_type.quantity,
              running: process_type.running
            }
          end,
          links: {
            outgoing_service_ids: service.linked_service_ids.map(&:to_s),
            incoming_service_ids: service.linked_by_service_ids.map(&:to_s)
          },
          variables: service.environment_variables.order(:key).map do |variable|
            { key: variable.key, source: variable.source, dokku_internal: !!variable.is_dokku_internal }
          end,
          config_keys: (service.config || {}).keys.sort,
          build: {
            builder: service.builder,
            framework: service.framework,
            branch: service.branch,
            docker_image: service.docker_image,
            root_directory: service.root_directory,
            start_command: service.start_command,
            static_site: service.config&.dig("staticSite").present?
          },
          restart_policy: service.restart_policy_value,
          maintenance_mode: service.maintenance_mode,
          webhook_configured: service.webhook_token.present?
        )
      end

      private

      attr_reader :service

      def id = service.id.to_s

      def domain(domain)
        {
          id: domain.id.to_s,
          hostname: domain.hostname,
          ssl: !!domain.ssl,
          temporary: !!domain.temporary,
          target_port: domain.resolved_target_port
        }
      end
    end
  end
end
