require "rails_helper"

RSpec.describe "Api::V1 OpenAPI document", type: :request do
  let(:user) { create(:user) }
  let(:organization) { create(:organization, owner: user) }
  let!(:membership) { create(:organization_membership, user: user, organization: organization, role: :owner) }

  def token
    ApiToken.issue!(organization: organization, user: user, name: "agent", scopes: [ "read" ])
  end

  def headers
    {
      "Authorization" => "Bearer #{token.plaintext}",
      "X-Organization-ID" => organization.id.to_s
    }
  end

  it "describes every v1 route" do
    get "/api/v1/openapi", headers: headers

    expect(response).to have_http_status(:ok)
    document = response.parsed_body
    expect(document["openapi"]).to start_with("3.1")
    expect(document.dig("info", "title")).to eq("RailDock Agent API")

    routes = Rails.application.routes.routes.filter_map do |route|
      spec = route.path.spec.to_s
      next unless spec.start_with?("/api/v1/")

      path = spec.sub("(.:format)", "").gsub(/:(\w+)/, '{\1}')
      [ path, route.verb.downcase ]
    end

    expect(routes).not_to be_empty
    routes.each do |path, verb|
      expect(document.dig("paths", path, verb)).to be_present, "missing #{verb.upcase} #{path}"
    end
  end

  it "keeps the documented error codes aligned with the surface" do
    get "/api/v1/openapi", headers: headers

    codes = response.parsed_body.dig("components", "schemas", "Error", "properties", "code", "description")
    expect(codes).to include("scope_denied", "plan_drifted", "removals_required", "rate_limited")
  end
end
