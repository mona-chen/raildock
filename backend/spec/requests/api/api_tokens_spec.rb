require "rails_helper"

RSpec.describe "Api tokens", type: :request do
  let(:user) { create(:user) }
  let(:organization) { create(:organization, owner: user) }
  let!(:membership) { create(:organization_membership, user: user, organization: organization, role: :owner) }
  let(:headers) do
    auth_headers(user).merge("X-Organization-ID" => organization.id.to_s, "Content-Type" => "application/json")
  end

  it "creates a token and reveals the secret only in that response" do
    expect {
      post "/api/api-tokens", params: { token: { name: "Claude Code", scopes: [ "deploy" ] } }.to_json, headers: headers
    }.to change(ApiToken, :count).by(1)

    expect(response).to have_http_status(:created)
    body = response.parsed_body
    expect(body["secret"]).to start_with(ApiToken::PREFIX)
    expect(body["token"]).to include("name" => "Claude Code", "scopes" => [ "read", "deploy" ])
    expect(body["token"]).not_to have_key("token_digest")

    get "/api/api-tokens", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include(body["secret"])
    expect(response.parsed_body["tokens"].first).not_to have_key("token_digest")
  end

  it "issues a token that authenticates the v1 API" do
    post "/api/api-tokens", params: { token: { name: "agent", scopes: [ "read" ] } }.to_json, headers: headers
    secret = response.parsed_body["secret"]

    get "/api/v1/context", headers: {
      "Authorization" => "Bearer #{secret}",
      "X-Organization-ID" => organization.id.to_s
    }

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("actor", "type")).to eq("api_token")
  end

  it "refuses a member who is not an admin" do
    member = create(:user)
    create(:organization_membership, user: member, organization: organization, role: :member)

    post "/api/api-tokens",
      params: { token: { name: "agent", scopes: [ "read" ] } }.to_json,
      headers: auth_headers(member).merge("X-Organization-ID" => organization.id.to_s, "Content-Type" => "application/json")

    expect(response).to have_http_status(:forbidden)
  end

  it "revokes a token so it can no longer authenticate" do
    token = ApiToken.issue!(organization: organization, user: user, name: "agent", scopes: [ "read" ])

    delete "/api/api-tokens/#{token.id}", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("token", "revoked_at")).to be_present

    get "/api/v1/context", headers: {
      "Authorization" => "Bearer #{token.plaintext}",
      "X-Organization-ID" => organization.id.to_s
    }

    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body["code"]).to eq("token_revoked")
  end

  it "rejects an expiry in the past" do
    post "/api/api-tokens",
      params: { token: { name: "agent", scopes: [ "read" ], expires_at: 1.hour.ago.iso8601 } }.to_json,
      headers: headers

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body["code"]).to eq("invalid_token")
  end

  it "rejects an unparseable expiry" do
    post "/api/api-tokens",
      params: { token: { name: "agent", scopes: [ "read" ], expires_at: "not-a-time" } }.to_json,
      headers: headers

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body["code"]).to eq("invalid_token")
  end

  it "requires an organization context" do
    post "/api/api-tokens",
      params: { token: { name: "agent", scopes: [ "read" ] } }.to_json,
      headers: auth_headers(user).merge("Content-Type" => "application/json")

    expect(response).to have_http_status(:forbidden)
  end
end
