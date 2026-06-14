require "rails_helper"

RSpec.describe PortDetector do
  let(:engine) { instance_double(DokkuEngine) }
  let(:host_engine) { instance_double(HostEngine) }
  let(:service) { build(:service, dokku_app_name: "example-app", docker_image: "example/image") }

  it "uses the lowest port exposed by the running container" do
    expect(engine).not_to receive(:run)
    allow(host_engine).to receive(:dokku_container_name).with("example-app").and_return("example-app.web.1")
    allow(host_engine).to receive(:docker_inspect).with(
      "example-app.web.1",
      format: "{{json .Config.ExposedPorts}}"
    ).and_return(success: true, output: '{"9001/tcp":{},"9000/tcp":{}}')

    port = described_class.new(engine, host_engine: host_engine).detect(service)

    expect(port).to eq(9000)
  end

  it "falls back to Dokku port reporting when the container is unavailable" do
    allow(host_engine).to receive(:dokku_container_name).with("example-app").and_return(nil)
    allow(engine).to receive(:run).with("ports:report example-app").and_return(
      success: true,
      output: "Ports map detected: http:80:8200\n"
    )

    port = described_class.new(engine, host_engine: host_engine).detect(service)

    expect(port).to eq(8200)
  end
end
