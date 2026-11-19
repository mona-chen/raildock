module Api
  module V1
    # Evidence for troubleshooting, composed from what RailDock already stores.
    # It deliberately performs no SSH: a diagnosis must be cheap, repeatable and
    # safe to call from an agent loop. Live container state is a separate call.
    class DiagnosisPresenter
      WINDOW = 1.hour
      DEPLOYMENTS = 5
      ACTIVITY = 10
      LOG_LINES = 80

      def initialize(service)
        @service = service
      end

      def as_json
        deployments = service.deployments.order(created_at: :desc).limit(DEPLOYMENTS).to_a
        samples = service.service_metrics.where(sampled_at: WINDOW.ago..).order(:sampled_at).to_a
        latest = deployments.first
        health_signals = signals(deployments)

        {
          service: ServicePresenter.new(service).summary,
          generated_at: Time.current.iso8601,
          status: {
            service: service.status,
            last_deployed: service.last_deployed,
            healthy: health_signals.empty?,
            signals: health_signals
          },
          deployments: deployments.map { |deployment| deployment(deployment) },
          build_log_tail: build_log_tail(latest),
          metrics: metrics(samples),
          activity: activity,
          limits: [
            "Diagnosis reads stored deployments, metrics and activity; it does not run commands on the host.",
            "Container metrics cover the primary container only and are not aggregated service usage.",
            "An empty metric window is reported as unavailable, not as zero usage."
          ]
        }
      end

      private

      attr_reader :service

      def signals(deployments)
        signals = []
        if service.status.present? && !%w[running deployed].include?(service.status.to_s)
          signals << "Service status is #{service.status}"
        end

        if (latest = deployments.first)
          signals << "Last deployment #{latest.status}" unless latest.succeeded?
        else
          signals << "No deployments recorded"
        end

        signals
      end

      def deployment(deployment)
        {
          id: deployment.id.to_s,
          status: deployment.status,
          kind: deployment.kind,
          branch: deployment.branch,
          commit_sha: deployment.commit_sha,
          started_at: deployment.started_at&.iso8601,
          completed_at: deployment.completed_at&.iso8601,
          duration_seconds: duration(deployment)
        }
      end

      def duration(deployment)
        return unless deployment.started_at && deployment.completed_at

        (deployment.completed_at - deployment.started_at).round
      end

      def build_log_tail(deployment)
        return unless deployment&.build_log.present?

        lines = deployment.build_log.to_s.lines
        {
          deployment_id: deployment.id.to_s,
          lines: lines.last(LOG_LINES).map { |line| LogRedactor.redact(line).chomp },
          truncated: lines.size > LOG_LINES
        }
      end

      def metrics(samples)
        base = {
          window_minutes: (WINDOW / 1.minute).to_i,
          collection_enabled: ObservabilitySettings.services_enabled?,
          samples: samples.size,
          available: samples.any?
        }
        return base unless samples.any?

        cpus = samples.filter_map(&:cpu)
        memories = samples.filter_map(&:memory_used)

        base.merge(
          cpu: cpus.any? ? { average: (cpus.sum / cpus.size).round(2), max: cpus.max } : nil,
          memory_used: memories.any? ? { max_bytes: memories.max } : nil
        )
      end

      def activity
        service.project.activity_events.order(created_at: :desc).limit(ACTIVITY).map do |event|
          {
            action: event.action,
            service: event.service_name,
            message: LogRedactor.redact(event.message.to_s),
            at: event.created_at.iso8601
          }
        end
      end
    end
  end
end
