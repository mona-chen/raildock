require "rails_helper"

RSpec.describe TerminalChannel, type: :channel do
  let(:user) { create(:user, admin: false) }
  let(:organization) { create(:organization) }
  let(:project) { create(:project, organization: organization) }
  let(:service) { create(:service, project: project) }
  let(:terminal_session) do
    instance_double(
      DokkuTerminalSession,
      on_open: nil,
      on_data: nil,
      on_close: nil,
      on_error: nil,
      open: true,
      close: nil
    )
  end

  before do
    create(:organization_membership, organization: organization, user: user, role: :admin)
    stub_connection current_user: user
    allow_any_instance_of(DokkuEngine).to receive(:interactive_shell).and_return(terminal_session)
  end

  it "confirms terminal access for an organization administrator" do
    subscribe(service_id: service.id, shell: "/bin/sh")

    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_for(service)
  end
end
