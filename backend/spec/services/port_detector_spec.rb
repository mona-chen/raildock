require "rails_helper"

RSpec.describe PortDetector do
  let(:engine) { instance_double(DokkuEngine) }
  let(:host_engine) { instance_double(HostEngine) }

  describe "priority order" do
    it "prefers the manifest-declared port over everything" do
      service = build(:service, dokku_app_name: "app", docker_image: "img", port: 3000)

      port = described_class.new(engine, host_engine: host_engine).detect(service)

      expect(port).to eq(3000)
    end

    it "prefers domain target_port over detected_port and Docker EXPOSE" do
      service = build(:service, dokku_app_name: "app", docker_image: "img", port: nil)
      create(:domain, service: service, target_port: 4000)

      # Even if Docker EXPOSE says 80, domain target_port should win
      allow(host_engine).to receive(:dokku_container_name).with("app").and_return("app.web.1")
      allow(host_engine).to receive(:docker_inspect).with(
        "app.web.1",
        format: "{{json .Config.ExposedPorts}}"
      ).and_return(success: true, output: '{"80/tcp":{}}')

      port = described_class.new(engine, host_engine: host_engine).detect(service)

      expect(port).to eq(4000)
    end

    it "falls back to ports:report when no manifest port or domain target_port" do
      service = build(:service, dokku_app_name: "app", docker_image: "img", port: nil)
      allow(host_engine).to receive(:dokku_container_name).with("app").and_return(nil)
      allow(host_engine).to receive(:docker_inspect).with(
        "dokku/app:latest",
        format: "{{json .Config.ExposedPorts}}"
      ).and_return(success: false, output: "")
      allow(engine).to receive(:run).with("ports:report app").and_return(
        success: true,
        output: "Ports map detected: http:80:8200\n"
      )

      port = described_class.new(engine, host_engine: host_engine).detect(service)

      expect(port).to eq(8200)
    end

    it "uses Docker EXPOSE when ports:report unavailable" do
      service = build(:service, dokku_app_name: "app", docker_image: "img", port: nil)
      allow(host_engine).to receive(:dokku_container_name).with("app").and_return("app.web.1")
      allow(host_engine).to receive(:docker_inspect).with(
        "app.web.1",
        format: "{{json .Config.ExposedPorts}}"
      ).and_return(success: true, output: '{"9001/tcp":{},"9000/tcp":{}}')
      allow(engine).to receive(:run).with("ports:report app").and_return(success: false)

      port = described_class.new(engine, host_engine: host_engine).detect(service)

      expect(port).to eq(9000)
    end

    it "returns lowest exposed port from Docker when ports:report fails" do
      service = build(:service, dokku_app_name: "app", docker_image: "img", port: nil)
      allow(host_engine).to receive(:dokku_container_name).with("app").and_return("app.web.1")
      allow(host_engine).to receive(:docker_inspect).with(
        "app.web.1",
        format: "{{json .Config.ExposedPorts}}"
      ).and_return(success: true, output: '{"9001/tcp":{},"9000/tcp":{}}')
      allow(engine).to receive(:run).with("ports:report app").and_return(success: false)

      port = described_class.new(engine, host_engine: host_engine).detect(service)

      expect(port).to eq(9000)
    end

    it "falls back to Dokku port reporting when the container is unavailable" do
      service = build(:service, dokku_app_name: "app", docker_image: "img", port: nil)
      allow(host_engine).to receive(:dokku_container_name).with("app").and_return(nil)
      allow(host_engine).to receive(:docker_inspect).with(
        "dokku/app:latest",
        format: "{{json .Config.ExposedPorts}}"
      ).and_return(success: false, output: "")
      allow(engine).to receive(:run).with("ports:report app").and_return(
        success: true,
        output: "Ports map detected: http:80:8200\n"
      )

      port = described_class.new(engine, host_engine: host_engine).detect(service)

      expect(port).to eq(8200)
    end

    it "detects from the built image while Dokku renames the container" do
      service = build(:service, dokku_app_name: "app", docker_image: "img", port: nil)
      allow(host_engine).to receive(:dokku_container_name).with("app").and_return(nil)
      allow(host_engine).to receive(:docker_inspect).with(
        "dokku/app:latest",
        format: "{{json .Config.ExposedPorts}}"
      ).and_return(success: true, output: '{"3000/tcp":{}}')
      allow(engine).to receive(:run).with("ports:report app").and_return(success: false)

      port = described_class.new(engine, host_engine: host_engine).detect(service)

      expect(port).to eq(3000)
    end
  end
end
