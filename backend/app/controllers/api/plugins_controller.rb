module Api
  class PluginsController < BaseController
    def index
      plugins = Plugin.enabled.includes(:service_subtypes).order(:name)
      render json: plugins.as_json(
        only: %i[id slug name description category icon status version],
        include: {
          service_subtypes: {
            only: %i[id subtype name description service_type default_version icon color capabilities env_var_prefix],
            methods: %i[url_var sslmode]
          }
        }
      )
    end
  end
end
