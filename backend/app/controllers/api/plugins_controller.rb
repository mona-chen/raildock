module Api
  class PluginsController < BaseController
    before_action :authorize_admin!, only: %i[enable disable install uninstall settings update_settings]

    def index
      plugins = Plugin.includes(:service_subtypes, :builders, :plugin_settings).order(:name)
      render json: plugins.as_json(
        only: %i[id slug name description category icon status version source_type source_url source_ref config_schema],
        include: {
          service_subtypes: {
            only: %i[id subtype name description service_type default_version icon color capabilities env_var_prefix config_schema],
            methods: %i[url_var sslmode]
          },
          builders: {
            only: %i[id slug name description dokku_builder source_types priority language_tags icon color config_schema status]
          },
          plugin_settings: {
            only: %i[id key value]
          }
        }
      )
    end

    def enable
      plugin = Plugin.find_by!(slug: params[:id])
      return render json: { error: "Built-in plugins are always enabled" }, status: :unprocessable_entity if plugin.built_in?

      plugin.update!(status: "enabled")
      PluginRegistry.clear_cache!
      render json: { success: true, plugin: plugin.as_json(only: %i[id slug name status]) }
    end

    def disable
      plugin = Plugin.find_by!(slug: params[:id])
      return render json: { error: "Built-in plugins cannot be disabled" }, status: :unprocessable_entity if plugin.built_in?

      plugin.update!(status: "disabled")
      PluginRegistry.clear_cache!
      render json: { success: true, plugin: plugin.as_json(only: %i[id slug name status]) }
    end

    def install
      source_url = install_params[:source_url].to_s.strip
      return render json: { error: "Source URL is required" }, status: :unprocessable_entity if source_url.blank?

      InstallPluginJob.perform_later(
        source_url: source_url,
        source_type: install_params[:source_type],
        source_ref: install_params[:source_ref]
      )

      render json: { success: true, message: "Plugin installation queued" }, status: :accepted
    end

    def uninstall
      plugin = Plugin.find_by!(slug: params[:id])
      return render json: { error: "Built-in plugins cannot be uninstalled" }, status: :unprocessable_entity if plugin.built_in?

      UninstallPluginJob.perform_later(plugin.id)
      render json: { success: true, message: "Plugin uninstallation queued" }, status: :accepted
    end

    def settings
      plugin = Plugin.find_by!(slug: params[:id])
      values = plugin.plugin_settings.each_with_object({}) do |setting, hash|
        hash[setting.key] = setting.value
      end
      render json: { slug: plugin.slug, settings: values }
    end

    def update_settings
      plugin = Plugin.find_by!(slug: params[:id])
      values = settings_params.to_h

      errors = ConfigSchema.validate(values, plugin.config_schema)
      return render json: { error: "Invalid settings", details: errors }, status: :unprocessable_entity if errors.any?

      PluginSetting.transaction do
        values.each do |key, value|
          setting = plugin.plugin_settings.find_or_initialize_by(key: key.to_s)
          setting.value = value
          setting.save!
        end
      end

      PluginRegistry.clear_cache!
      render json: { success: true, settings: plugin.plugin_settings.each_with_object({}) { |s, h| h[s.key] = s.value } }
    end

    private

    def authorize_admin!
      unless current_user&.admin?
        render json: { error: "Forbidden - admin access required" }, status: :forbidden
      end
    end

    def install_params
      params.permit(:source_url, :source_type, :source_ref)
    end

    def settings_params
      params.require(:settings).to_unsafe_h
    end
  end
end
