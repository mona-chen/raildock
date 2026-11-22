require "rails_helper"
require "tempfile"

RSpec.describe HostEngine do
  describe "#run_with_file" do
    it "streams the whole file to the SSH channel" do
      server = create(:server)
      engine = described_class.new(server)

      channel_class = Class.new do
        attr_reader :sent

        def initialize
          @sent = []
        end

        def exec(_command)
          yield self, true
        end

        def send_data(data)
          @sent << data
        end

        def eof!; end

        def on_data(&block)
          @on_data = block
        end

        def on_extended_data(&block)
          @on_extended_data = block
        end

        def on_request(_name, &block)
          @on_request = block
        end

        def wait
          @on_data&.call(nil, "uploaded\n")
          @on_request&.call(nil, Struct.new(:read_long).new(0))
        end
      end

      channel = channel_class.new
      ssh = Object.new
      ssh.define_singleton_method(:open_channel) do |&block|
        block.call(channel)
        channel
      end

      allow(engine).to receive(:execute_on_session).and_yield(ssh)

      file = Tempfile.new("host-engine-payload")
      file.write("hello from the host")
      file.flush

      result = engine.run_with_file("cat", file.path)

      expect(channel.sent.join).to eq("hello from the host")
      expect(result).to include(success: true)
      expect(result[:output]).to include("uploaded")
    ensure
      file&.close!
    end
  end
end
