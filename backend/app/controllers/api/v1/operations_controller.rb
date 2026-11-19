module Api
  module V1
    class OperationsController < BaseController
      def show
        return unless require_scope!(:read)

        operation = scoped_operations.find(params[:id])
        return render json: { error: "Not found" }, status: :not_found unless visible?(operation)

        render json: { operation: OperationPresenter.new(operation).as_json }
      end

      private

      # A token bound to a project or environment must not be able to poll work
      # outside its binding, even if it guesses an operation id.
      def visible?(operation)
        return false if operation.project_id && !scoped_projects.exists?(id: operation.project_id)
        return false if operation.service_id && !scoped_services.exists?(id: operation.service_id)

        true
      end
    end
  end
end
