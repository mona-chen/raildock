module Api
  module Admin
    class UpdatesController < BaseController
      before_action :authorize_admin!

      # GET /api/admin/update
      # Returns current version, last check info, and auto-update setting
      def index
        render json: AppUpdateService.last_check_result.merge(
          auto_update_enabled: AppUpdateService.auto_update_enabled?
        )
      end

      # POST /api/admin/update/check
      # Triggers a manual check for updates
      def check
        result = AppUpdateService.check_for_updates

        if result
          render json: result.merge(
            auto_update_enabled: AppUpdateService.auto_update_enabled?
          )
        else
          error = SystemSetting.find_by(key: "update_check_error")&.value || "Unknown error"
          render json: { error: error }, status: :service_unavailable
        end
      end

      # POST /api/admin/update/apply
      # Applies the available update
      def apply
        result = AppUpdateService.apply_update

        if result[:success]
          render json: result
        else
          render json: { error: result[:error] }, status: :unprocessable_entity
        end
      end

      # PATCH /api/admin/update/auto-update
      # Toggles auto-update setting
      def auto_update
        enabled = params[:enabled] == true || params[:enabled] == "true"
        AppUpdateService.set_auto_update(enabled)
        render json: { auto_update_enabled: enabled }
      end

      private

      def authorize_admin!
        unless current_user&.admin?
          render json: { error: "Forbidden - admin access required" }, status: :forbidden
        end
      end
    end
  end
end
