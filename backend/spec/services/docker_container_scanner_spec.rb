require "rails_helper"

RSpec.describe DockerContainerScanner do
  let(:organization) { create(:organization) }
  let(:server) { create(:server, organization: organization) }
  let(:scanner) { described_class.new(server) }
  let(:host_engine) { instance_double(HostEngine) }

  before do
    allow(HostEngine).to receive(:new).with(server).and_return(host_engine)
  end

  def container_json(attrs = {})
    {
      "Id" => SecureRandom.hex(32),
      "Names" => ["/web-app"],
      "Created" => Time.current.iso8601,
      "State" => { "Status" => "running", "Running" => true },
      "Config" => {
        "Image" => "myapp/web:latest",
        "Hostname" => "web-app",
        "Cmd" => ["node", "server.js"],
        "Env" => ["PORT=3000", "NODE_ENV=production"],
        "ExposedPorts" => { "3000/tcp" => {} },
        "Labels" => { "foo" => "bar" }
      },
      "HostConfig" => {
        "PortBindings" => { "3000/tcp" => [{ "HostIp" => "0.0.0.0", "HostPort" => "8080" }] },
        "Binds" => ["/data/uploads:/app/uploads:rw"]
      },
      "Mounts" => [
        { "Source" => "/data/uploads", "Destination" => "/app/uploads", "Type" => "bind", "Mode" => "rw" }
      ]
    }.merge(attrs).to_json
  end

  describe "#scan" do
    it "returns parsed containers" do
      allow(host_engine).to receive(:run).and_return(success: true, output: container_json)

      result = scanner.scan
      expect(result[:success]).to be true
      expect(result[:containers].length).to eq(1)

      container = result[:containers].first
      expect(container[:name]).to eq("web-app")
      expect(container[:image]).to eq("myapp/web:latest")
      expect(container[:running]).to be true
      expect(container[:ports]).to include(hash_including(container_port: "3000", host_port: "8080"))
      expect(container[:env]).to eq({ "PORT" => "3000", "NODE_ENV" => "production" })
      expect(container[:mounts]).to include(hash_including(source: "/data/uploads", destination: "/app/uploads", type: "bind"))
      expect(container[:service_type]).to eq("app")
    end

    it "classifies database images" do
      db_json = container_json(
        "Names" => ["/postgres-db"],
        "Config" => {
          "Image" => "postgres:16-alpine",
          "Hostname" => "postgres-db",
          "Env" => ["POSTGRES_PASSWORD=secret"],
          "ExposedPorts" => { "5432/tcp" => {} },
          "Labels" => {}
        },
        "HostConfig" => { "PortBindings" => {}, "Binds" => [] },
        "Mounts" => []
      )

      allow(host_engine).to receive(:run).and_return(success: true, output: db_json)

      result = scanner.scan
      container = result[:containers].first
      expect(container[:service_type]).to eq("database")
      expect(container[:subtype]).to eq("postgres")
    end

    it "returns an empty list when there are no containers" do
      allow(host_engine).to receive(:run).and_return(success: true, output: "")
      result = scanner.scan
      expect(result[:success]).to be true
      expect(result[:containers]).to be_empty
    end

    it "returns an error when the host command fails" do
      allow(host_engine).to receive(:run).and_return(success: false, output: "docker daemon not running")
      result = scanner.scan
      expect(result[:success]).to be false
      expect(result[:error]).to eq("docker daemon not running")
    end
  end
end
