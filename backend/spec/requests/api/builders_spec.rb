require 'rails_helper'

RSpec.describe "Builders API", type: :request do
  let(:user) { create(:user) }
  let(:auth_headers) { { "Authorization" => "Bearer #{user.generate_jwt}" } }

  describe "GET /api/builders" do
    it "returns the list of builders without auth" do
      get "/api/builders"
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json).to be_an(Array)
      expect(json.first).to include("id", "name")
    end
  end
end
