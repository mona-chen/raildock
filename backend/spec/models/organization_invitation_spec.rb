require "rails_helper"

RSpec.describe OrganizationInvitation, type: :model do
  let(:inviter) { create(:user) }
  let(:org) { create(:organization, owner: inviter) }

  it "generates a token and an expiry on create" do
    inv = OrganizationInvitation.create!(
      organization: org,
      invited_by: inviter,
      email: "test@example.com"
    )
    expect(inv.token).to be_present
    expect(inv.expires_at).to be_within(1.minute).of(7.days.from_now)
  end

  it "is invalid for an existing member" do
    existing = create(:user, email: "alreadymember@example.com")
    create(:organization_membership, user: existing, organization: org, role: :member)

    inv = OrganizationInvitation.new(
      organization: org,
      invited_by: inviter,
      email: "alreadymember@example.com"
    )
    expect(inv).not_to be_valid
    expect(inv.errors[:email]).to be_present
  end

  it "scopes pending invitations correctly" do
    pending = OrganizationInvitation.create!(
      organization: org, invited_by: inviter, email: "p@example.com"
    )
    expired = OrganizationInvitation.create!(
      organization: org, invited_by: inviter, email: "e@example.com",
      expires_at: 1.day.ago
    )
    accepted = OrganizationInvitation.create!(
      organization: org, invited_by: inviter, email: "a@example.com",
      accepted_at: Time.current
    )

    expect(OrganizationInvitation.pending).to contain_exactly(pending)
  end
end