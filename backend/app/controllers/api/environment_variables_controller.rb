module Api
  class EnvironmentVariablesController < BaseController
    include Authorizable
    before_action :set_and_authorize_service!

    def create
      ev = @service.environment_variables.create!(env_var_params)

      # Sync to Dokku
      sync_to_dokku(:set, ev.key, ev.value)

      render json: ev, status: :created
    end

    def destroy
      ev = @service.environment_variables.find_by!(key: params[:key])

      # Sync to Dokku
      sync_to_dokku(:unset, ev.key)

      ev.destroy!
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

    def sync_to_dokku(action, key, value = nil)
      return unless @service.project&.server&.ssh_key.present?

      engine = DokkuEngine.new(@service.project.server)
      if action == :set
        engine.config_set(@service.dokku_app_name, key, value)
      else
        engine.config_unset(@service.dokku_app_name, key)
      end
    end
  end
end
