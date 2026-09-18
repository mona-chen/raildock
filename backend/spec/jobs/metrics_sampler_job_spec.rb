require "rails_helper"

RSpec.describe MetricsSamplerJob, type: :job do
  let!(:server) { create(:server) }
  let!(:project) { create(:project, server: server) }
  let!(:service) { create(:service, project: project, docker_image: "nginx:latest", status: :running) }
  let(:host_engine) { instance_double(HostEngine) }

  before do
    allow(HostEngine).to receive(:new).with(server).and_return(host_engine)
    allow(host_engine).to receive(:dokku_container_name).with(service.dokku_app_name).and_return("app.web.1")
    allow(host_engine).to receive(:docker_stats).and_return(
      cpu: 35.5, memory: 50.0, memory_used: 1073741824, memory_limit: 2147483648
    )
  end

  it "persists a metric sample for each deployed docker service" do
    expect {
      MetricsSamplerJob.perform_now
    }.to change(ServiceMetric, :count).by(1)

    metric = ServiceMetric.last
    expect(metric.service).to eq(service)
    expect(metric.cpu).to eq(35.5)
    expect(metric.memory).to eq(50.0)
    expect(metric.sampled_at).to be_present
  end

  it "persists network and disk I/O counters" do
    allow(host_engine).to receive(:docker_stats).and_return(
      cpu: 10.0, memory: 25.0, memory_used: 1024, memory_limit: 4096,
      network_rx: 2048, network_tx: 4096, block_read: 8192, block_write: 16_384
    )

    MetricsSamplerJob.perform_now

    metric = ServiceMetric.last
    expect(metric.network_in).to eq(2048)
    expect(metric.network_out).to eq(4096)
    expect(metric.block_read).to eq(8192)
    expect(metric.block_write).to eq(16_384)
  end

  it "skips services without a docker image" do
    service.update!(docker_image: nil)
    expect { MetricsSamplerJob.perform_now }.not_to change(ServiceMetric, :count)
  end

  it "skips services whose container is not running" do
    allow(host_engine).to receive(:dokku_container_name).and_return(nil)
    expect { MetricsSamplerJob.perform_now }.not_to change(ServiceMetric, :count)
  end

  it "prunes samples older than retention" do
    old = create(:service_metric, service: service, sampled_at: 40.days.ago)
    MetricsSamplerJob.perform_now
    expect(ServiceMetric.exists?(old.id)).to be(false)
  end
end
