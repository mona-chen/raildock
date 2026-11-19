module Api
  module V1
    class ProjectPresenter
      def initialize(project)
        @project = project
      end

      def as_json
        {
          id: project.id.to_s,
          name: project.name,
          description: project.description,
          environment: project.environment,
          deletion: {
            pending: project.deletion_pending?,
            status: project.deletion_status,
            error: project.deletion_error,
            error_code: project.deletion_error_code,
            requested_at: project.deletion_requested_at&.iso8601
          },
          manifest: {
            configured: project.manifest_content.present?,
            format: project.manifest_format,
            synced: project.manifest_synced?,
            drift_detected: project.manifest_drift_detected,
            last_applied_at: project.manifest_last_applied_at&.iso8601
          },
          environments: project.environments.sort_by(&:name).map do |environment|
            {
              id: environment.id.to_s,
              name: environment.name,
              slug: environment.slug,
              is_default: environment.is_default
            }
          end,
          services: project.services.sort_by(&:name).map { |service| ServicePresenter.new(service).summary },
          links: links
        }
      end

      private

      attr_reader :project

      def links
        ids = project.services.map(&:id)
        return [] if ids.empty?

        ServiceLink.where(from_service_id: ids, to_service_id: ids).map do |link|
          { from_service_id: link.from_service_id.to_s, to_service_id: link.to_service_id.to_s }
        end
      end
    end
  end
end
