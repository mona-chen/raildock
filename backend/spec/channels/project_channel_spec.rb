require "rails_helper"

RSpec.describe ProjectChannel, type: :channel do
  let(:user) { create(:user, admin: false) }

  before { stub_connection current_user: user }

  it "streams projects the user belongs to" do
    organization = create(:organization)
    create(:organization_membership, organization: organization, user: user)
    project = create(:project, organization: organization)

    subscribe(project_id: project.id)

    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_for(project)
  end

  it "rejects inaccessible personal projects" do
    project = create(:project, user: create(:user, admin: false))

    subscribe(project_id: project.id)

    expect(subscription).to be_rejected
  end
end
