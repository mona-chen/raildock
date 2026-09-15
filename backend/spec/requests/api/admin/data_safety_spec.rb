require "rails_helper"

RSpec.describe "Api::Admin::DataSafetyController", type: :request do
  let(:admin) { create(:user) }
  let(:user) { create(:user, admin: false) }

  it "reports data-loss risks to admins" do
    server = create(:server)
    create(:service, :database, project: create(:project, server: server), name: "shop-db")

    get "/api/admin/data-safety", headers: auth_headers(admin)

    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body["findings"].map { |finding| finding["code"] }).to include("unprotected_datastore")
    expect(body.dig("summary", "critical")).to be >= 1
  end

  it "forbids non-admins" do
    get "/api/admin/data-safety", headers: auth_headers(user)

    expect(response).to have_http_status(:forbidden)
  end
end
