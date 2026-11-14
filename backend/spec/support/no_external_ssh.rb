# Unit/request specs must never contact a random factory host. Individual SSH
# adapter tests override this with an explicit connection double. The Docker
# integration spec runs its commands locally and does not need SSH.
RSpec.configure do |config|
  config.before do
    allow(Net::SSH).to receive(:start) do
      raise RSpec::Mocks::MockExpectationError, "Unexpected SSH connection in a test; stub Net::SSH.start or the host adapter explicitly"
    end
  end
end
