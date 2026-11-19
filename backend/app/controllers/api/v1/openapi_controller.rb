module Api
  module V1
    class OpenapiController < BaseController
      def show
        return unless require_scope!(:read)

        render json: AgentApiDocument.new.as_json
      end
    end
  end
end
