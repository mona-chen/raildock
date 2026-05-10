require 'rails_helper'

RSpec.describe "Networks API", type: :request do
  let(:user) { create(:user) }
  let(:auth_headers) { { "Authorization" => "Bearer #{user.generate_jwt}" } }

  describe "GET /api/networks" do
    it "returns the list of networks" do
      get "/api/networks", headers: auth_headers
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json).to be_an(Array)
    end

    it "returns 200 without auth" do
      get "/api/networks"
      expect(response).to have_http_status(:ok)
    end
  end
end
