require "rails_helper"

RSpec.describe HttpTrafficSetup do
  include ActiveSupport::Testing::TimeHelpers
  let(:server) { create(:server) }
  let(:setup) { described_class.new(server) }
  let(:document) do
    { "services" => { "traefik" => { "image" => "traefik:v3.6", "command" => [ "--providers.docker=true", "--entrypoints.web.address=:80", "--accesslog.format=common" ], "volumes" => [ "/certs:/certs" ], "ports" => [ "80:80" ], "labels" => { "routing" => "unchanged" } }, "other" => { "image" => "postgres", "environment" => { "PASSWORD" => "synthetic-private-value" } } }, "networks" => { "proxy" => { "external" => true } } }
  end
  let(:candidate) { { "container" => "coolify-proxy", "container_id" => "abc123", "digest" => "reviewed-digest", "can_manage" => true, "service" => "traefik", "compose_b64" => Base64.strict_encode64(YAML.dump(document)) } }
  let(:token) { setup.discover[:candidates].first.fetch("review_token") }

  before { allow(setup).to receive(:remote).with("discover").and_return([ candidate ]) }

  it "never exposes Compose secrets or private source content in discovery" do
    result = setup.discover.to_json
    expect(result).to include("review_token", "coolify-proxy")
    expect(result).not_to include("synthetic-private-value", "compose_b64", "reviewed-digest")
  end

  it "binds approval to the server and rejects expired or modified tokens" do
    other = described_class.new(create(:server))
    expect { other.verify!(token) }.to raise_error(described_class::Error)
    expect { setup.verify!(token + "x") }.to raise_error(described_class::Error)
    travel 16.minutes do
      expect { setup.verify!(token) }.to raise_error(described_class::Error)
    end
  end

  it "refuses changed sources before attempting a host write" do
    reviewed = token
    allow(setup).to receive(:remote).with("discover").and_return([ candidate.merge("digest" => "changed") ])
    expect(setup).not_to receive(:remote).with("apply", anything)
    expect { setup.apply(reviewed) }.to raise_error(described_class::Error, /changed/)
  end

  it "changes only logging options and the log mount, preserving routing and other services" do
    expect(setup).to receive(:remote).with("apply", anything) do |_, plan|
      updated = YAML.safe_load(Base64.strict_decode64(plan["compose_b64"]))
      proxy = updated["services"]["traefik"]
      expect(proxy["command"]).to include("--providers.docker=true", "--entrypoints.web.address=:80", "--accesslog.format=json")
      expect(proxy["command"]).not_to include("--accesslog.format=common")
      expect(proxy["command"].join).not_to include("ClientAddr", "RequestPath=keep")
      expect(proxy.except("command", "volumes")).to eq(document["services"]["traefik"].except("command", "volumes"))
      expect(updated["services"]["other"]).to eq(document["services"]["other"])
      expect(updated["networks"]).to eq(document["networks"])
      expect(proxy["volumes"]).to include("/certs:/certs", "/var/log/raildock-http/coolify-proxy:/var/log/raildock-http/coolify-proxy")
      { "path" => "/var/log/raildock-http/coolify-proxy/access.log" }
    end
    setup.apply(token)
  end
end
