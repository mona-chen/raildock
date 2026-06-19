module Api
  class EnvironmentVariablesController < BaseController
    include Authorizable
    before_action :set_and_authorize_service!

    def create
      # Upsert: update existing env var or create new one
      ev = @service.environment_variables.find_or_initialize_by(key: env_var_params[:key])
      ev.assign_attributes(env_var_params)
      ev.save!

      sync_env_to_dokku

      render json: ev, status: ev.previously_new_record? ? :created : :ok
    end

    def destroy
      ev = @service.environment_variables.find_by!(key: params[:key])

      ev.destroy!
      sync_env_to_dokku

      head :no_content
    end

    private

    def set_and_authorize_service!
      @service = Service.find(params[:service_id])
      authorize_service!(@service)
    end

    def env_var_params
      params.permit(:key, :value, :source, :is_dokku_internal)
    end

    # Batched atomic write — replaces the per-key `config:set` calls that
    # were vulnerable to partial writes corrupting the host ENV file.
    def sync_env_to_dokku
      return unless @service.project&.server&.ssh_key.present?

      env_hash = @service.environment_variables.where(is_dokku_internal: [ false, nil ]).pluck(:key, :value).to_h

      DokkuEnvSyncer.sync(
        server: @service.project.server,
        app_name: @service.dokku_app_name,
        desired_env: env_hash
      )
    rescue DokkuEnvSyncer::EnvCorruptError, DokkuEnvSyncer::SyncFailedError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end
  end
end
