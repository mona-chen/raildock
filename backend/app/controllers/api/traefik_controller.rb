module Api
  class TraefikController < BaseController
    include Authorizable

    before_action :set_server

    def show
      authorize_server!(action: :read)
      render json: TraefikOverview.new(@server).call
    end

    def logs
      authorize_server!(action: :read)
      result = TraefikLogs.new(@server).call(lines: params[:lines], container: params[:container])
      if result[:success]
        render json: result
      else
        render json: result, status: result[:output].present? ? :bad_gateway : :unprocessable_entity
      end
    end

    def update
      authorize_server!(action: :update)
      operation = params[:operation].to_s
      return unprocessable("Choose an operation", "invalid_operation") unless %w[start stop restart check].include?(operation)

      if operation == "check"
        return unprocessable("Routing checks are available for external proxies", "not_external_proxy") unless @server.external_proxy?

        ProxyDriftCheckJob.perform_later(@server.id)
        return render json: { accepted: true, operation: operation }, status: :accepted
      end

      return unprocessable("External Traefik is read-only in RailDock", "external_proxy_read_only") if @server.external_proxy?

      if %w[stop restart].include?(operation) && params[:confirmation].to_s != @server.name
        return render json: {
          error: "Confirm the server name before interrupting every app behind this proxy",
          code: "confirmation_required"
        }, status: :precondition_required
      end

      result = perform_operation(operation)
      Rails.logger.info({ event: "audit", action: "server.traefik.#{operation}", server_id: @server.id, user_id: current_user.id, success: result[:success] }.to_json)

      if result[:success]
        render json: { success: true, operation: operation, output: redact(result[:output]) }
      else
        render json: {
          error: result[:error] || "Traefik #{operation} failed",
          output: redact(result[:output]),
          partial: result[:partial] == true
        }, status: result[:partial] ? :bad_gateway : :unprocessable_entity
      end
    end

    private

    def set_server
      @server = scoped_servers.find(params[:server_id])
    end

    def perform_operation(operation)
      engine = DokkuEngine.new(@server)
      case operation
      when "start"
        engine.traefik_start
      when "stop"
        engine.traefik_stop
      when "restart"
        stopped = engine.traefik_stop
        return { success: false, error: "Traefik could not be stopped; it was not restarted", output: stopped[:output] } unless stopped[:success]

        started = engine.traefik_start
        started.merge(partial: !started[:success], error: started[:success] ? nil : "Traefik stopped but could not be started again")
      end
    end

    def unprocessable(message, code)
      render json: { error: message, code: code }, status: :unprocessable_entity
    end

    def redact(output)
      LogRedactor.redact(output.to_s).last(4_000)
    end
  end
end
