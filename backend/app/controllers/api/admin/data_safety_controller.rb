module Api
  module Admin
    class DataSafetyController < BaseController
      before_action :authorize_admin!

      # GET /api/admin/data-safety
      # Instance-wide audit of data that is one failure away from being lost.
      def index
        render json: DataSafetyReport.new.call
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
