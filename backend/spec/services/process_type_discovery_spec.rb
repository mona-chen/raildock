require "rails_helper"

RSpec.describe ProcessTypeDiscovery do
  let(:engine) { instance_double(DokkuEngine) }
  let(:service) { create(:service, dokku_app_name: "tween-tween-pay") }
  subject(:discovery) { described_class.new(engine) }

  # Verbatim `dokku ps:scale <app>` output from the host. Note that a type
  # scaled to zero still appears here even though ps:report omits it.
  let(:ps_scale_output) do
    <<~OUTPUT
      -----> Scaling for tween-tween-pay
      proctype: qty
      --------: ---
      release: 0
      web:  1
      worker: 0
    OUTPUT
  end

  before do
    allow(engine).to receive(:ps_scale_report)
      .with("tween-tween-pay")
      .and_return(success: true, output: ps_scale_output)
  end

  describe "#sync" do
    it "records every declared process type, seeded from the running quantity" do
      result = discovery.sync(service)

      expect(result[:success]).to be true
      expect(service.process_types.pluck(:name, :quantity)).to contain_exactly([ "web", 1 ], [ "worker", 0 ])
    end

    it "exposes a worker that Dokku left at zero so it can be scaled up" do
      discovery.sync(service)

      expect(service.process_types.find_by(name: "worker")).to have_attributes(quantity: 0, running: 0)
    end

    it "does not record one-shot deploy tasks such as release" do
      discovery.sync(service)

      expect(service.process_types.pluck(:name)).not_to include("release")
    end

    it "is idempotent across repeated deploys" do
      discovery.sync(service)
      discovery.sync(service)

      expect(service.process_types.count).to eq(2)
    end

    it "preserves a quantity the user chose instead of resetting it to Dokku's" do
      discovery.sync(service)
      service.process_types.find_by(name: "worker").update!(quantity: 3)

      discovery.sync(service)

      expect(service.process_types.find_by(name: "worker").quantity).to eq(3)
    end

    it "picks up a process type added to the Procfile later" do
      discovery.sync(service)

      allow(engine).to receive(:ps_scale_report).with("tween-tween-pay").and_return(
        success: true,
        output: "proctype: qty\n--------: ---\nweb:  1\nworker: 1\nclock: 0\n"
      )
      discovery.sync(service)

      expect(service.process_types.pluck(:name)).to contain_exactly("web", "worker", "clock")
    end

    it "reports the quantities it recorded" do
      expect(discovery.sync(service)[:discovered].map { |pt| pt[:name] }).to include("worker")
    end

    it "fails without touching the DB when Dokku cannot be reached" do
      allow(engine).to receive(:ps_scale_report).and_return(success: false, output: "Permission denied")

      result = discovery.sync(service)

      expect(result[:success]).to be false
      expect(result[:error]).to include("Permission denied")
      expect(service.process_types.count).to eq(0)
    end

    it "fails when Dokku returns no process types" do
      allow(engine).to receive(:ps_scale_report).and_return(success: true, output: "")

      expect(discovery.sync(service)).to include(success: false)
    end
  end

  describe "#parse" do
    it "ignores the header rows" do
      expect(discovery.parse(ps_scale_output)).to eq("web" => 1, "worker" => 0)
    end

    it "returns nil when nothing usable is present" do
      expect(discovery.parse("-----> Scaling for app\n")).to be_nil
    end
  end
end
