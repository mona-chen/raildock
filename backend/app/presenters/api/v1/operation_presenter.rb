module Api
  module V1
    # A uniform envelope over asynchronous work. Status is derived from the
    # authoritative record when one exists, so polling never disagrees with the
    # deployment or manifest operation it points at.
    class OperationPresenter
      def initialize(operation)
        @operation = operation
      end

      def as_json
        {
          id: operation.id.to_s,
          kind: operation.kind,
          status: operation.status,
          project_id: operation.project_id&.to_s,
          service_id: operation.service_id&.to_s,
          subject: subject,
          created_at: operation.created_at&.iso8601,
          started_at: operation.started_at&.iso8601,
          completed_at: operation.completed_at&.iso8601,
          error: operation.error,
          result: result
        }
      end

      private

      attr_reader :operation

      def subject
        return if operation.subject_type.blank?

        { type: operation.subject_type, id: operation.subject_id&.to_s }
      end

      def result
        case operation.subject
        when Deployment
          {
            deployment_id: operation.subject.id.to_s,
            deployment_kind: operation.subject.kind,
            deployment_status: operation.subject.status
          }
        when ManifestOperation
          {
            manifest_operation_id: operation.subject.id.to_s,
            manifest_status: operation.subject.status
          }
        when Project
          { deletion_status: operation.subject.deletion_status } if operation.kind == "project_deletion"
        end
      end
    end
  end
end
