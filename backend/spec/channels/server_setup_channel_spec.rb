require "rails_helper"

RSpec.describe ServerSetupChannel, type: :channel do
  let(:user) { create(:user, admin: false) }
  let(:organization) { create(:organization, owner: user) }
  let!(:membership) { create(:organization_membership, user: user, organization: organization, role: :owner) }
  let(:setup_id) { SecureRandom.uuid }

  around do |example|
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    example.run
    Rails.cache = original
  end

  it "streams a setup started by the user's organization" do
    Server.record_setup_owner!(setup_id, organization_id: organization.id, user_id: user.id)
    stub_connection current_user: user

    subscribe(setup_id: setup_id)

    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_from("server_setup:#{setup_id}")
  end

  it "rejects a setup started by another organization" do
    stranger = create(:user, admin: false)
    other_org = create(:organization, owner: stranger)
    Server.record_setup_owner!(setup_id, organization_id: other_org.id, user_id: stranger.id)
    stub_connection current_user: user

    subscribe(setup_id: setup_id)

    expect(subscription).to be_rejected
  end

  it "rejects unknown setup ids" do
    stub_connection current_user: user
    subscribe(setup_id: setup_id)
    expect(subscription).to be_rejected
  end
end
