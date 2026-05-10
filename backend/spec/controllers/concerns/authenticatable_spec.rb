require 'rails_helper'

RSpec.describe Authenticatable, type: :controller do
  controller(Api::BaseController) do
    def index
      render json: { user_id: current_user.id }
    end
  end

  let(:user) { create(:user) }
  let(:valid_token) { user.generate_jwt }

  describe "#authenticate_user!" do
    it "allows access with valid token" do
      request.headers["Authorization"] = "Bearer #{valid_token}"
      get :index
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["user_id"]).to eq(user.id)
    end

    it "rejects access without token" do
      get :index
      expect(response).to have_http_status(:unauthorized)
      expect(JSON.parse(response.body)["error"]).to eq("Unauthorized")
    end

    it "rejects access with invalid token" do
      request.headers["Authorization"] = "Bearer invalid.token.here"
      get :index
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
