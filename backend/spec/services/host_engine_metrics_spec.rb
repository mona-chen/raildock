require "rails_helper"

RSpec.describe HostEngine do
  it "samples all containers with one stats process and preserves fractional CPU" do
    engine = described_class.new(create(:server))
    allow(engine).to receive(:with_session).and_yield
    allow(engine).to receive(:run).with("docker stats --no-stream --format '{{json .}}'").and_return(success: true, output: [
      { Name: "site.web.1", CPUPerc: "0.05%", MemUsage: "10MiB / 1GiB", NetIO: "1kB / 2kB", BlockIO: "0B / 3kB" }.to_json,
      { Name: "site.worker.1", CPUPerc: "12.5%", MemUsage: "20MiB / 1GiB", NetIO: "2kB / 4kB", BlockIO: "0B / 0B" }.to_json
    ].join("\n"))
    allow(engine).to receive(:run).with("docker ps -q | xargs -r docker inspect --format '{{.Name}} {{.HostConfig.NanoCpus}}'").and_return(success: true, output: "/site.web.1 500000000\n/site.worker.1 0\n")
    result = engine.docker_stats_snapshot
    expect(result.keys).to contain_exactly("site.web.1", "site.worker.1")
    expect(result["site.web.1"]).to include(cpu: 0.05, cpu_cores: 0.5, memory_used: 10 * 1024 * 1024)
  end
end
