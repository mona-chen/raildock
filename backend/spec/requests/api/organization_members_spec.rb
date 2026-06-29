require "rails_helper"

RSpec.describe "Organization members end-to-end flow", type: :request do
  describe "bootstrap → create org → invite → accept → manage members" do
    it "works end to end" do
      # ── 1. Bootstrap: first user auto-creates personal org ──────────────────
      post "/api/users", params: {
        user: { name: "Alice", email: "alice@example.com", password: "password123" }
      }
      expect(response).to have_http_status(:created)
      bootstrap_json = JSON.parse(response.body)
      alice_token = bootstrap_json["token"]

      # Response includes personal org at the top level
      personal_org = bootstrap_json["organization"]
      expect(personal_org).to be_present
      expect(personal_org["role"]).to eq("owner")
      expect(personal_org["name"]).to include("Alice")

      # user payload includes the org in the organizations array
      expect(bootstrap_json["user"]["organizations"]).to be_present
      expect(bootstrap_json["user"]["organizations"].first["role"]).to eq("owner")

      alice = User.find_by!(email: "alice@example.com")
      personal_id = personal_org["id"]
      expect(personal_org["member_count"]).to eq(1)

      alice_headers = { "Authorization" => "Bearer #{alice_token}" }

      # ── 2. Me returns the org ──────────────────────────────────────────────
      get "/api/me", headers: alice_headers
      expect(response).to have_http_status(:ok)
      me_json = JSON.parse(response.body)
      expect(me_json["organizations"].length).to be >= 1
      expect(me_json["organizations"].first["id"]).to eq(personal_id)

      # ── 3. Create a new organization (team workspace) ──────────────────────
      post "/api/organizations",
        params: { organization: { name: "Acme Corp", slug: "acme-corp" } },
        headers: alice_headers
      expect(response).to have_http_status(:created)
      org_json = JSON.parse(response.body)
      org_id = org_json["id"]
      expect(org_json["name"]).to eq("Acme Corp")
      expect(org_json["member_count"]).to eq(1)
      expect(org_json["role"]).to eq("owner")

      # ── 4. List members (just Alice) ────────────────────────────────────────
      get "/api/organizations/#{org_id}/members", headers: alice_headers
      expect(response).to have_http_status(:ok)
      members = JSON.parse(response.body)
      expect(members.length).to eq(1)
      expect(members.first["role"]).to eq("owner")
      expect(members.first["isYou"]).to be true
      expect(members.first["user"]["email"]).to eq("alice@example.com")

      # ── 5. Invite a new user (no account yet) ───────────────────────────────
      post "/api/organizations/#{org_id}/invitations",
        params: { email: "bob@example.com", role: "admin" },
        headers: alice_headers
      expect(response).to have_http_status(:created)
      invite_json = JSON.parse(response.body)
      expect(invite_json["email"]).to eq("bob@example.com")
      expect(invite_json["role"]).to eq("admin")
      expect(invite_json["existing_user"]).to be false
      expect(invite_json["accept_url"]).to include("/invitations/")

      invitation_token = invite_json["accept_url"].split("/").last

      # ── 6. View invitation details (unauthenticated) ───────────────────────
      get "/api/invitations/#{invitation_token}"
      expect(response).to have_http_status(:ok)
      details = JSON.parse(response.body)
      expect(details["invitation"]["email"]).to eq("bob@example.com")
      expect(details["invitation"]["role"]).to eq("admin")
      expect(details["invitation"]["existing_user"]).to be false
      expect(details["invitation"]["organization"]["name"]).to eq("Acme Corp")

      # ── 7. Accept invitation as a new user ─────────────────────────────────
      post "/api/invitations/#{invitation_token}/accept",
        params: { name: "Bob", password: "bobpass123" }
      expect(response).to have_http_status(:ok)
      accept_json = JSON.parse(response.body)
      expect(accept_json["token"]).to be_present
      expect(accept_json["new_account"]).to be true
      expect(accept_json["organization"]["role"]).to eq("admin")

      bob = User.find_by!(email: "bob@example.com")
      bob_headers = { "Authorization" => "Bearer #{accept_json["token"]}" }

      # ── 8. Verify both members in the org ──────────────────────────────────
      get "/api/organizations/#{org_id}/members", headers: alice_headers
      expect(response).to have_http_status(:ok)
      members = JSON.parse(response.body)
      expect(members.length).to eq(2)

      alice_member = members.find { |m| m["user"]["email"] == "alice@example.com" }
      bob_member = members.find { |m| m["user"]["email"] == "bob@example.com" }
      expect(alice_member["role"]).to eq("owner")
      expect(alice_member["isYou"]).to be true
      expect(bob_member["role"]).to eq("admin")
      expect(bob_member["isYou"]).to be false

      # ── 9. Bob's me also shows the org ─────────────────────────────────────
      get "/api/me", headers: bob_headers
      expect(response).to have_http_status(:ok)
      bob_me = JSON.parse(response.body)
      orgs = bob_me["organizations"].map { |o| [ o["id"], o["role"] ] }.to_h
      expect(orgs[org_id]).to eq("admin")

      # ── 10. Change Bob's role to member ────────────────────────────────────
      patch "/api/organizations/#{org_id}/members/#{bob.id}",
        params: { role: "member" },
        headers: alice_headers
      expect(response).to have_http_status(:ok)
      updated = JSON.parse(response.body)
      expect(updated["role"]).to eq("member")

      get "/api/organizations/#{org_id}/members", headers: alice_headers
      members = JSON.parse(response.body)
      bob_member = members.find { |m| m["user"]["email"] == "bob@example.com" }
      expect(bob_member["role"]).to eq("member")

      # ── 11. Non-admin cannot change roles ──────────────────────────────────
      patch "/api/organizations/#{org_id}/members/#{alice.id}",
        params: { role: "member" },
        headers: bob_headers
      expect(response).to have_http_status(:forbidden)

      # ── 12. Remove Bob from the org ────────────────────────────────────────
      delete "/api/organizations/#{org_id}/members/#{bob.id}",
        headers: alice_headers
      expect(response).to have_http_status(:no_content)

      get "/api/organizations/#{org_id}/members", headers: alice_headers
      members = JSON.parse(response.body)
      expect(members.length).to eq(1)
      expect(members.first["user"]["email"]).to eq("alice@example.com")

      # ── 13. Invite an existing user ────────────────────────────────────────
      post "/api/organizations/#{org_id}/invitations",
        params: { email: "bob@example.com" },
        headers: alice_headers
      expect(response).to have_http_status(:created)
      reinvite_json = JSON.parse(response.body)
      expect(reinvite_json["existing_user"]).to be true

      invitation_token = reinvite_json["accept_url"].split("/").last

      # ── 14. Existing user accepts with password proof ──────────────────────
      post "/api/invitations/#{invitation_token}/accept",
        params: { password: "bobpass123" }
      expect(response).to have_http_status(:ok)
      accept_json = JSON.parse(response.body)
      expect(accept_json["new_account"]).to be false
      expect(accept_json["user"]["id"]).to eq(bob.id)

      # ── 15. Revoke an invitation ──────────────────────────────────────────
      post "/api/organizations/#{org_id}/invitations",
        params: { email: "carol@example.com", role: "member" },
        headers: alice_headers
      expect(response).to have_http_status(:created)
      invite_id = JSON.parse(response.body)["id"]

      expect {
        delete "/api/organizations/#{org_id}/invitations/#{invite_id}",
          headers: alice_headers
      }.to change(OrganizationInvitation, :count).by(-1)
      expect(response).to have_http_status(:no_content)

      # ── 16. Cannot remove the last owner ──────────────────────────────────
      delete "/api/organizations/#{org_id}/members/#{alice.id}",
        headers: alice_headers
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "existing user without org gets personal org on login" do
    it "auto-creates a personal org for legacy users" do
      legacy = create(:user, name: "Legacy User", email: "legacy@example.com")

      expect(legacy.organizations.count).to eq(0)

      post "/api/login", params: { email: "legacy@example.com", password: "password123" }
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)

      expect(json["user"]["organizations"].length).to eq(1)
      org = json["user"]["organizations"].first
      expect(org["role"]).to eq("owner")
      expect(org["name"]).to include("Legacy User")
      expect(org["member_count"]).to eq(1)

      token = json["token"]
      get "/api/me", headers: { "Authorization" => "Bearer #{token}" }
      expect(response).to have_http_status(:ok)
      me_json = JSON.parse(response.body)
      expect(me_json["organizations"].length).to eq(1)
    end

    it "adopts orphaned projects into the personal org" do
      legacy = create(:user)
      project = create(:project, user: legacy, organization: nil)

      expect(project.reload.organization_id).to be_nil

      post "/api/login", params: { email: legacy.email, password: "password123" }

      org = legacy.reload.organizations.first
      expect(org).to be_present
      expect(project.reload.organization_id).to eq(org.id)
    end

    it "adopts orphaned deploy keys into the personal org" do
      legacy = create(:user)
      deploy_key = create(:deploy_key, user: legacy, organization: nil)

      expect(deploy_key.reload.organization_id).to be_nil

      post "/api/login", params: { email: legacy.email, password: "password123" }

      org = legacy.reload.organizations.first
      expect(deploy_key.reload.organization_id).to eq(org.id)
    end
  end

  describe "member management edge cases" do
    let(:owner) { create(:user) }
    let(:org) { create(:organization, owner: owner) }
    let(:owner_headers) { auth_headers(owner) }

    before do
      create(:organization_membership, user: owner, organization: org, role: :owner)
    end

    it "cannot change role of the last owner" do
      patch "/api/organizations/#{org.id}/members/#{owner.id}",
        params: { role: "member" },
        headers: owner_headers
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "owner can promote a member to owner" do
      member = create(:user)
      create(:organization_membership, user: member, organization: org, role: :member)

      patch "/api/organizations/#{org.id}/members/#{member.id}",
        params: { role: "owner" },
        headers: owner_headers
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["role"]).to eq("owner")
    end

    it "non-owner cannot promote to owner" do
      alice = create(:user)
      bob = create(:user)
      create(:organization_membership, user: alice, organization: org, role: :member)
      create(:organization_membership, user: bob, organization: org, role: :member)

      patch "/api/organizations/#{org.id}/members/#{bob.id}",
        params: { role: "owner" },
        headers: auth_headers(alice)
      expect(response).to have_http_status(:forbidden)
    end

    it "member can leave (remove themselves)" do
      member = create(:user)
      create(:organization_membership, user: member, organization: org, role: :member)
      member_headers = auth_headers(member)

      delete "/api/organizations/#{org.id}/members/#{member.id}",
        headers: member_headers
      expect(response).to have_http_status(:no_content)
    end

    it "admin can remove a member" do
      admin = create(:user)
      member = create(:user)
      create(:organization_membership, user: admin, organization: org, role: :admin)
      create(:organization_membership, user: member, organization: org, role: :member)

      delete "/api/organizations/#{org.id}/members/#{member.id}",
        headers: auth_headers(admin)
      expect(response).to have_http_status(:no_content)
    end

    it "owner cannot be removed" do
      delete "/api/organizations/#{org.id}/members/#{owner.id}",
        headers: owner_headers
      expect(response).to have_http_status(:forbidden)
    end

    it "returns 404 for membership that does not exist" do
      patch "/api/organizations/#{org.id}/members/99999999",
        params: { role: "member" },
        headers: owner_headers
      expect(response).to have_http_status(:not_found)
    end

    it "forbids non-member from viewing members" do
      stranger = create(:user)
      get "/api/organizations/#{org.id}/members", headers: auth_headers(stranger)
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "invitation edge cases" do
    let(:owner) { create(:user) }
    let(:org) { create(:organization, owner: owner) }
    let(:headers) { auth_headers(owner) }

    before do
      create(:organization_membership, user: owner, organization: org, role: :owner)
    end

    it "rejects inviting an existing member" do
      member = create(:user, email: "member@example.com")
      create(:organization_membership, user: member, organization: org, role: :member)

      post "/api/organizations/#{org.id}/invitations",
        params: { email: "member@example.com" },
        headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns 410 for expired invitations" do
      invitation = OrganizationInvitation.create!(
        organization: org,
        invited_by: owner,
        email: "someone@example.com",
        role: "member",
        expires_at: 1.day.ago
      )

      get "/api/invitations/#{invitation.token}"
      expect(response).to have_http_status(:gone)

      post "/api/invitations/#{invitation.token}/accept",
        params: { name: "Late", password: "password123" }
      expect(response).to have_http_status(:gone)
    end

    it "is idempotent on double accept" do
      invitation = OrganizationInvitation.create!(
        organization: org,
        invited_by: owner,
        email: "newguy@example.com",
        role: "member"
      )

      post "/api/invitations/#{invitation.token}/accept",
        params: { name: "New Guy", password: "password123" }
      expect(response).to have_http_status(:ok)

      post "/api/invitations/#{invitation.token}/accept",
        params: { name: "Again", password: "password123" }
      expect(response).to have_http_status(:gone)
    end
  end
end
