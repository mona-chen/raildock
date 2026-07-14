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

    it "detects from the running container's listening sockets before EXPOSE" do
      service = build(:service, dokku_app_name: "app", docker_image: "img", port: nil)
      allow(host_engine).to receive(:dokku_container_name).with("app").and_return("app.web.1")
      allow(host_engine).to receive(:run).with("docker exec app.web.1 sh -c 'cat /proc/net/tcp /proc/net/tcp6 2>/dev/null'")
        .and_return(success: true, output: "  0: 0000000000000000:0BB8 0000000000000000:0000 0A 00000000:00000000 00:00000000 00000000  1000 0 12345 1 0000000000000000 100 0 0 10 0\n")
      allow(host_engine).to receive(:docker_inspect).with(
        "app.web.1",
        format: "{{json .Config.ExposedPorts}}"
      ).and_return(success: true, output: '{"80/tcp":{}}')

      port = described_class.new(engine, host_engine: host_engine).detect(service)

      expect(port).to eq(3000)
    end

    it "detect_actual ignores the manifest-declared port and returns the listening port" do
      service = build(:service, dokku_app_name: "app", docker_image: "img", port: 5173)
      allow(host_engine).to receive(:dokku_container_name).with("app").and_return("app.web.1")
      allow(host_engine).to receive(:run).with("docker exec app.web.1 sh -c 'cat /proc/net/tcp /proc/net/tcp6 2>/dev/null'")
        .and_return(success: true, output: "  0: 00000000:0BB8 00000000:0000 0A 00000000:00000000 00:00000000 00000000  1000 0 12345 1 0000000000000000 100 0 0 10 0\n")

      port = described_class.new(engine, host_engine: host_engine).detect_actual(service)

      expect(port).to eq(3000)
    end

    it "prefers all-interface listeners over loopback-only listeners" do
      service = build(:service, dokku_app_name: "app", docker_image: "img", port: nil)
      allow(host_engine).to receive(:dokku_container_name).with("app").and_return("app.web.1")
      allow(host_engine).to receive(:run).with("docker exec app.web.1 sh -c 'cat /proc/net/tcp /proc/net/tcp6 2>/dev/null'")
        .and_return(success: true, output: <<~TCP)
            0: 0B00007F:1435 00000000:0000 0A 00000000:00000000 00:00000000 00000000  1000 0 12345 1 0000000000000000 100 0 0 10 0
            1: 00000000:0BB8 00000000:0000 0A 00000000:00000000 00:00000000 00000000  1000 0 12346 1 0000000000000000 100 0 0 10 0
        TCP

      port = described_class.new(engine, host_engine: host_engine).detect_actual(service)

      expect(port).to eq(3000)
    end

    it "uses Docker EXPOSE when the container has no listening sockets" do
      service = build(:service, dokku_app_name: "app", docker_image: "img", port: nil)
      allow(host_engine).to receive(:dokku_container_name).with("app").and_return("app.web.1")
      allow(host_engine).to receive(:run).with("docker exec app.web.1 sh -c 'cat /proc/net/tcp /proc/net/tcp6 2>/dev/null'")
        .and_return(success: true, output: "")
      allow(host_engine).to receive(:docker_inspect).with(
        "app.web.1",
        format: "{{json .Config.ExposedPorts}}"
      ).and_return(success: true, output: '{"9001/tcp":{},"9000/tcp":{}}')

      port = described_class.new(engine, host_engine: host_engine).detect(service)

      expect(port).to eq(9000)
    end

    it "falls back to ports:report when the container and EXPOSE are unavailable" do
      service = build(:service, dokku_app_name: "app", docker_image: "img", port: nil)
      allow(host_engine).to receive(:dokku_container_name).with("app").and_return(nil)
      allow(host_engine).to receive(:run).with("docker exec app.web.1 sh -c 'cat /proc/net/tcp /proc/net/tcp6 2>/dev/null'")
        .and_return(success: false, output: "")
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
      allow(host_engine).to receive(:run).with("docker exec app.web.1 sh -c 'cat /proc/net/tcp /proc/net/tcp6 2>/dev/null'")
        .and_return(success: false, output: "")
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
