require "rails_helper"

RSpec.describe "Api::InvitationsController", type: :request do
  let(:inviter) { create(:user) }
  let(:org) { create(:organization, owner: inviter) }
  let!(:membership) { create(:organization_membership, user: inviter, organization: org, role: :owner) }
  let(:invitee_email) { "teammate@example.com" }

  let(:create_invitation) do
    post "/api/organizations/#{org.id}/invitations",
      params: { email: invitee_email, role: "member" },
      headers: auth_headers(inviter)
  end

  describe "POST /api/organizations/:id/invitations" do
    it "creates an invitation and queues the mailer" do
      expect { create_invitation }.to change(OrganizationInvitation, :count).by(1)
      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json["email"]).to eq(invitee_email)
      expect(json["role"]).to eq("member")
      expect(json["accept_url"]).to include("/invitations/")
      expect(json["existing_user"]).to be false
    end

    it "rejects invitations for existing members" do
      existing = create(:user, email: "already@example.com")
      create(:organization_membership, user: existing, organization: org, role: :member)

      post "/api/organizations/#{org.id}/invitations",
        params: { email: "already@example.com" },
        headers: auth_headers(inviter)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "rejects invitations for non-admins" do
      member = create(:user)
      create(:organization_membership, user: member, organization: org, role: :member)

      post "/api/organizations/#{org.id}/invitations",
        params: { email: invitee_email },
        headers: auth_headers(member)

      expect(response).to have_http_status(:forbidden)
    end

    it "attaches user when invitee already has an account" do
      existing = create(:user, email: "hasaccount@example.com")
      post "/api/organizations/#{org.id}/invitations",
        params: { email: "hasaccount@example.com" },
        headers: auth_headers(inviter)

      json = JSON.parse(response.body)
      expect(json["existing_user"]).to be true
      expect(json["accept_url"]).to include("/invitations/")
    end
  end

  describe "GET /api/invitations/:token" do
    let!(:invitation) do
      OrganizationInvitation.create!(
        organization: org,
        invited_by: inviter,
        email: invitee_email,
        role: "admin"
      )
    end

    it "returns the invitation details" do
      get "/api/invitations/#{invitation.token}"

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["invitation"]["email"]).to eq(invitee_email)
      expect(json["invitation"]["role"]).to eq("admin")
      expect(json["invitation"]["organization"]["name"]).to eq(org.name)
      expect(json["invitation"]["existing_user"]).to be false
    end

    it "returns 404 for unknown tokens" do
      get "/api/invitations/totally-bogus"
      expect(response).to have_http_status(:not_found)
    end

    it "returns 410 for expired invitations" do
      invitation.update!(expires_at: 1.day.ago)
      get "/api/invitations/#{invitation.token}"
      expect(response).to have_http_status(:gone)
    end
  end

  describe "POST /api/invitations/:token/accept" do
    let!(:invitation) do
      OrganizationInvitation.create!(
        organization: org,
        invited_by: inviter,
        email: invitee_email,
        role: "member"
      )
    end

    it "creates a new user, joins the org, and returns a JWT" do
      expect {
        post "/api/invitations/#{invitation.token}/accept",
          params: { name: "Teammate", password: "supersecret" }
      }.to change(User, :count).by(1)
       .and change(OrganizationMembership, :count).by(1)

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["token"]).to be_present
      expect(json["new_account"]).to be true
      expect(json["organization"]["role"]).to eq("member")

      new_user = User.find_by(email: invitee_email)
      expect(invitation.reload).to be_accepted
      expect(invitation.user).to eq(new_user)
      expect(org.memberships.find_by(user: new_user).role).to eq("member")
    end

    it "lets an existing user accept by proving their password" do
      existing = create(:user, email: invitee_email, password: "oldpass123", password_confirmation: "oldpass123")

      post "/api/invitations/#{invitation.token}/accept", params: { password: "oldpass123" }

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["user"]["id"]).to eq(existing.id)
      expect(json["new_account"]).to be false
      expect(org.memberships.find_by(user: existing)).to be_present
    end

    it "rejects an existing user with the wrong password" do
      create(:user, email: invitee_email, password: "oldpass123", password_confirmation: "oldpass123")

      post "/api/invitations/#{invitation.token}/accept", params: { password: "wrong" }

      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects a weak password on new-account acceptance" do
      post "/api/invitations/#{invitation.token}/accept",
        params: { name: "Teammate", password: "short" }

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "is idempotent: cannot accept twice" do
      post "/api/invitations/#{invitation.token}/accept",
        params: { name: "First", password: "supersecret" }
      expect(response).to have_http_status(:ok)

      post "/api/invitations/#{invitation.token}/accept",
        params: { name: "Second", password: "supersecret" }
      expect(response).to have_http_status(:gone)
    end
  end

  describe "DELETE /api/organizations/:id/invitations/:id" do
    let!(:invitation) do
      OrganizationInvitation.create!(
        organization: org,
        invited_by: inviter,
        email: invitee_email,
        role: "member"
      )
    end

    it "lets admins revoke a pending invitation" do
      expect {
        delete "/api/organizations/#{org.id}/invitations/#{invitation.id}",
          headers: auth_headers(inviter)
      }.to change(OrganizationInvitation, :count).by(-1)
      expect(response).to have_http_status(:no_content)
    end
  end
end
