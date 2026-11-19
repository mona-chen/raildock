module Api
  module V1
    class ServicesController < BaseController
      before_action :require_read_scope, only: [ :show, :logs, :diagnose ]

      def show
        render json: ServicePresenter.new(service).as_json
      end

      def logs
        limit = params[:lines].present? ? params[:lines].to_i.clamp(1, 500) : 100

        render json: logs_payload(service, limit)
      end

      def diagnose
        render json: DiagnosisPresenter.new(service).as_json
      end

      def deploy
        return unless require_scope!(:deploy)

        target = service
        authorize_service!(target, action: :deploy)

        if target.service_type == "database"
          return render json: {
            error: "Database services cannot be deployed. They are managed directly by Dokku.",
            code: "not_deployable"
          }, status: :unprocessable_entity
        end

        start_operation(
          service: target,
          kind: "deploy",
          deployment_attributes: {
            kind: "deploy",
            status: "pending",
            started_at: Time.current,
            branch: params[:branch] || target.branch || "main",
            commit_sha: params[:commit_sha],
            commit_message: params[:commit_message],
            triggered_by: "manual"
          }
        ) do |deployment|
          DeploymentJob.perform_later(target.id, deployment.id, api_token_id: current_api_token&.id)
          target.update!(status: :deploying)
          ActivityEvent.create!(
            project: target.project,
            service_name: target.name,
            action: :deployed,
            message: "Deployment triggered for #{target.name}",
            api_token: current_api_token
          )
        end
      end

      def restart
        return unless require_scope!(:deploy)

        target = service
        authorize_service!(target, action: :restart)

        if target.project&.server&.ssh_key.blank?
          return render json: {
            error: "No server SSH key configured for this service",
            code: "server_unavailable"
          }, status: :unprocessable_entity
        end

        start_operation(
          service: target,
          kind: "restart",
          deployment_attributes: {
            kind: "restart",
            status: "pending",
            started_at: Time.current,
            branch: target.branch,
            triggered_by: "manual",
            build_log: "",
            deploy_log: ""
          }
        ) do |deployment|
          RestartJob.perform_later(
            target.id,
            idempotency_key: deployment.idempotency_key,
            api_token_id: current_api_token&.id
          )
        end
      end

      private

      # Deploy and restart are async and therefore must be retry-safe. The
      # operation is keyed by the caller's Idempotency-Key, and the deployment
      # it points at is keyed by the same value, so a retry attaches to the work
      # already started instead of building a second one.
      def start_operation(service:, kind:, deployment_attributes:)
        key = idempotency_key!
        return unless key

        fingerprint = "#{kind}:#{service.id}"
        if (existing = find_operation(key))
          return render_idempotency_conflict unless existing.request_fingerprint == fingerprint

          return render_operation(existing, status: :ok)
        end

        deployment, created = Deployment.create_idempotently!(
          service: service,
          key: "agent-#{current_organization.id}-#{key}",
          attributes: deployment_attributes
        )

        operation = Operation.create_or_find_by!(
          organization: current_organization,
          idempotency_key: key
        ) do |record|
          record.kind = kind
          record.project = service.project
          record.service = service
          record.subject = deployment
          record.request_fingerprint = fingerprint
          record.api_token = current_api_token
        end

        return render_idempotency_conflict unless operation.request_fingerprint == fingerprint

        yield(deployment) if created

        render_operation(operation, status: created ? :accepted : :ok)
      end

      def require_read_scope
        require_scope!(:read)
      end

      def service
        @service ||= scoped_services.find(params[:id])
      end

      def logs_payload(service, limit)
        live, error = live_logs(service, limit)
        return live if live

        payload = {
          service_id: service.id.to_s,
          source: "stored",
          truncated: false,
          lines: service.logs.last(limit).map do |entry|
            {
              timestamp: entry[:timestamp]&.iso8601,
              process_type: entry[:process_type],
              message: LogRedactor.redact(entry[:message].to_s)
            }
          end
        }
        payload[:error] = error if error
        payload
      end

      # Live logs require the service's host. When the host is missing or the
      # command fails, the caller gets stored deployment logs and an explicit
      # reason instead of an empty list that looks like "no traffic".
      def live_logs(service, limit)
        server = service.project&.server
        return [ nil, nil ] unless server&.ssh_key.present?

        engine = DokkuEngine.new(server)
        result = if service.subtype_record&.has_capability?(:logs)
          engine.datastore_logs(service)
        else
          engine.logs(service.dokku_app_name, lines: limit)
        end
        return [ nil, LogRedactor.redact(result[:output].to_s) ] unless result[:success]

        output = result[:output].to_s.lines
        [
          {
            service_id: service.id.to_s,
            source: "host",
            truncated: output.size > limit,
            lines: output.last(limit).map do |line|
              {
                timestamp: Time.current.iso8601,
                process_type: service.subtype,
                message: LogRedactor.redact(line).chomp
              }
            end
          },
          nil
        ]
      rescue StandardError => error
        [ nil, LogRedactor.redact(error.message) ]
      end
    end
  end
end
