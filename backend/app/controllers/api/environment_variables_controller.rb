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
      return sync_error_response(sync_result) if sync_result.is_a?(Hash) && sync_result[:error]

      restart_deployment_id = trigger_restart_after_env_change

      render json: ev.as_json.merge(restart_deployment_id: restart_deployment_id).compact,
             status: ev.previously_new_record? ? :created : :ok
    end

    def destroy
      ev = @service.environment_variables.find_by!(key: params[:key])

      ev.destroy!
      sync_result = sync_env_to_dokku
      return sync_error_response(sync_result) if sync_result.is_a?(Hash) && sync_result[:error]

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

    def sync_error_response(sync_result)
      render json: { error: sync_result[:error] }, status: sync_result[:status] || :unprocessable_entity
    end

    # Batched atomic write — replaces the per-key `config:set` calls that
    # were vulnerable to partial writes corrupting the host ENV file.
    def sync_env_to_dokku
      return { success: true } unless @service.project&.server&.ssh_key.present?

      env_hash = @service.environment_variables.where(is_dokku_internal: [ false, nil ]).pluck(:key, :value).to_h

      DokkuEnvSyncer.sync(
        server: @service.project.server,
        app_name: @service.dokku_app_name,
        desired_env: env_hash
      )
      { success: true }
    rescue DokkuEnvSyncer::EnvCorruptError, DokkuEnvSyncer::SyncFailedError => e
      { error: e.message, status: :unprocessable_entity }
    end

    # Schedule a restart so new env values take effect in the running
    # container. The restart appears in the Deploy tab as a tracked
    # Deployment of kind "restart" with streamed logs. We pass a nonce
    # so two env saves in quick succession get separate Deployment records
    # (idempotency_key makes them unique), but the same nonce reused
    # (e.g. on retry) reuses the existing record.
    def trigger_restart_after_env_change
      return nil unless @service.project&.server&.ssh_key.present?

      idempotency_key = "env-restart:#{@service.id}:#{SecureRandom.hex(4)}"
      RestartJob.perform_later(@service.id, idempotency_key: idempotency_key)

      # Best-effort: return the deployment_id if the job has already
      # created one synchronously (rare in production); nil otherwise.
      Deployment.find_by(idempotency_key: idempotency_key)&.id
    end
  end
end
