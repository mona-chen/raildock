module Api
  module V1
    class ServicesController < BaseController
      before_action :require_read_scope

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

      private

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
