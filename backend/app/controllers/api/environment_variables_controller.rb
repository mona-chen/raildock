module Api
  class EnvironmentVariablesController < BaseController
    include Authorizable
    before_action :set_and_authorize_service!

    def create
      # Upsert: update existing env var or create new one
      ev = @service.environment_variables.find_or_initialize_by(key: env_var_params[:key])
      ev.assign_attributes(env_var_params)
      ev.save!

      sync_result = sync_env_to_dokku
      if sync_result[:error]
        return render json: { error: sync_result[:error] },
                      status: sync_result[:status] || :unprocessable_entity
      end

      restart_deployment_id = trigger_restart_after_env_change

      render json: ev.as_json.merge(restart_deployment_id: restart_deployment_id).compact,
             status: ev.previously_new_record? ? :created : :ok
    end

    def destroy
      ev = @service.environment_variables.find_by!(key: params[:key])

      ev.destroy!
      sync_result = sync_env_to_dokku
      if sync_result[:error]
        return render json: { error: sync_result[:error] },
                      status: sync_result[:status] || :unprocessable_entity
      end

      restart_deployment_id = trigger_restart_after_env_change

      render json: { restart_deployment_id: restart_deployment_id }
    end

    private

    def set_and_authorize_service!
      @service = Service.find(params[:service_id])
      authorize_service!(@service)
    end

    def env_var_params
      params.permit(:key, :value, :source, :is_dokku_internal)
    end

    # Sync the entire desired env state to Dokku in one batched call:
    #   1. config:clear         (one SSH round trip, removes all old vars)
    #   2. config:set --no-restart K1=V1 K2=V2 ...  (one SSH round trip)
    #
    # Dokku's godotenv-based read is lenient on partial corruption (more
    # than bash `source`), so even a file with tail fragments like
    # `dcheap.us/apps"` gets cleanly replaced with the canonical state.
    def sync_env_to_dokku
      return { success: true } unless @service.project&.server&.ssh_key.present?

      env_hash = @service.environment_variables.where(is_dokku_internal: [ false, nil ]).pluck(:key, :value).to_h

      engine = DokkuEngine.new(@service.project.server)
      result = engine.config_replace_all(@service.dokku_app_name, env_hash)

      if result[:success]
        { success: true }
      else
        { error: result[:error] || "Sync failed: #{result[:output].to_s.truncate(300)}",
          status: :unprocessable_entity }
      end
    end

    # Schedule a restart so new env values take effect in the running
    # container. The restart appears in the Deploy tab as a tracked
    # Deployment of kind "restart" with streamed logs.
    def trigger_restart_after_env_change
      return nil unless @service.project&.server&.ssh_key.present?

      idempotency_key = "env-restart:#{@service.id}:#{SecureRandom.hex(4)}"
      RestartJob.perform_later(@service.id, idempotency_key: idempotency_key)
      Deployment.find_by(idempotency_key: idempotency_key)&.id
    end
  end
end
