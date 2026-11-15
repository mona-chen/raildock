require "rails_helper"

RSpec.describe MetricsSamplerJob, type: :job do
  let!(:server) { create(:server) }
  let!(:project) { create(:project, server: server) }
  let!(:service) { create(:service, project: project, docker_image: "nginx:latest", status: :running) }
  let(:host_engine) { instance_double(HostEngine) }

  before do
    allow(HostEngine).to receive(:new).with(server).and_return(host_engine)
    allow(HostMetricsCollector).to receive(:call)
    allow(host_engine).to receive(:docker_stats_snapshot).and_return(
      "#{service.dokku_app_name}.web.1" => { cpu: 35.5, memory: 50.0, memory_used: 1073741824, memory_limit: 2147483648 }
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
    allow(host_engine).to receive(:docker_stats_snapshot).and_return(
      "#{service.dokku_app_name}.web.1" => { cpu: 10.0, memory: 25.0, memory_used: 1024, memory_limit: 4096,
      network_rx: 2048, network_tx: 4096, block_read: 8192, block_write: 16_384 }
    )

    MetricsSamplerJob.perform_now

    metric = ServiceMetric.last
    expect(metric.network_in).to eq(2048)
    expect(metric.network_out).to eq(4096)
    expect(metric.block_read).to eq(8192)
    expect(metric.block_write).to eq(16_384)
  end

  it "samples Git-deployed apps without a docker image field" do
    service.update!(docker_image: nil)
    expect { MetricsSamplerJob.perform_now }.to change(ServiceMetric, :count).by(1)
  end

  it "skips stopped services" do
    service.update!(status: :stopped)
    expect { MetricsSamplerJob.perform_now }.not_to change(ServiceMetric, :count)
  end

  it "skips services whose container is not running" do
    allow(host_engine).to receive(:docker_stats_snapshot).and_return({})
    expect { MetricsSamplerJob.perform_now }.not_to change(ServiceMetric, :count)
  end

  it "stops container sampling when disabled but still expires old data" do
    SystemSetting.set!("metrics_services_enabled", "false")
    old = create(:service_metric, service: service, sampled_at: 40.days.ago)
    MetricsSamplerJob.perform_now
    expect(ServiceMetric.exists?(old.id)).to be(false)
    expect(host_engine).not_to have_received(:docker_stats_snapshot)
  end

  it "uses the configured retention period" do
    SystemSetting.set!("metrics_retention_days", "7")
    old = create(:service_metric, service: service, sampled_at: 8.days.ago)
    MetricsSamplerJob.perform_now
    expect(ServiceMetric.exists?(old.id)).to be(false)
  end

  it "prunes samples older than retention" do
    old = create(:service_metric, service: service, sampled_at: 40.days.ago)
    MetricsSamplerJob.perform_now
    expect(ServiceMetric.exists?(old.id)).to be(false)
  end
end
