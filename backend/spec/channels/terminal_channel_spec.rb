require "rails_helper"

RSpec.describe TerminalChannel, type: :channel do
  let(:user) { create(:user, admin: false) }
  let(:organization) { create(:organization) }
  let(:project) { create(:project, organization: organization) }
  let(:service) { create(:service, project: project) }
  let(:terminal_session) do
    session = DokkuTerminalSession.allocate
    session.instance_variable_set(:@callbacks, {})
    session.instance_variable_set(:@shell, "/bin/zsh")
    session
  end

  before do
    create(:organization_membership, organization: organization, user: user, role: :admin)
    stub_connection current_user: user
    allow_any_instance_of(DokkuEngine).to receive(:interactive_shell).and_return(terminal_session)
    # Run the SSH setup synchronously so we can assert on the resulting
    # callbacks and on_error / on_close wiring. The original implementation
    # offloads this to a thread for production; tests need it inline.
    allow(Thread).to receive(:new) { |&block| block.call; instance_double(Thread, kill: nil) }
  end

  it "confirms terminal access for an organization administrator" do
    subscribe(service_id: service.id, shell: "/bin/sh")

    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_for(service)
    expect(Thread).to have_received(:new)
  end

  describe "missing shell recovery" do
    let(:error_messages) { [] }
    let(:fallback_session) do
      session = DokkuTerminalSession.allocate
      session.instance_variable_set(:@callbacks, {})
      session.instance_variable_set(:@shell, "/bin/sh")
      session.instance_variable_set(:@opened, true)
      session.define_singleton_method(:open) { |&_b| @open_block_called = true; true }
      session.define_singleton_method(:close) { @closed = true }
      session
    end

    before do
      # First interactive_shell call returns the original (broken) session;
      # the retry returns the working /bin/sh session.
      allow_any_instance_of(DokkuEngine).to receive(:interactive_shell) do |_engine, _app, **opts|
        opts[:shell] == "/bin/sh" ? fallback_session : terminal_session
      end
      allow_any_instance_of(TerminalChannel).to receive(:transmit) { |_, payload| error_messages << payload }
    end

    it "retries with /bin/sh when the selected shell reports a missing-file error" do
      subscribe(service_id: service.id, shell: "/bin/zsh")
      expect(subscription).to be_confirmed

      # Capture the original session's on_error callback, then trigger it
      # as the SSH channel would when the OCI exec failure closes the PTY.
      original_callbacks = terminal_session.instance_variable_get(:@callbacks)
      original_callbacks[:on_error]&.call(
        "Shell /bin/zsh is not available in this container. Try /bin/sh or /bin/bash instead."
      )

      # The channel must have surfaced the original error to the client
      # and then opened a fresh session for /bin/sh.
      expect(error_messages.any? { |m| m[:type] == "error" && m[:data].to_s.include?("/bin/zsh") }).to be(true)
      expect(fallback_session.instance_variable_get(:@open_block_called)).to be(true)
    end

    it "does not loop forever if the fallback shell also fails" do
      fallback_callbacks = nil

      subscribe(service_id: service.id, shell: "/bin/zsh")
      expect(subscription).to be_confirmed

      original_callbacks = terminal_session.instance_variable_get(:@callbacks)
      original_callbacks[:on_error]&.call(
        "Shell /bin/zsh is not available in this container. Try /bin/sh or /bin/bash instead."
      )

      fallback_callbacks = fallback_session.instance_variable_get(:@callbacks)
      expect(fallback_callbacks[:on_error]).to be_a(Proc)
    end
  end
end
