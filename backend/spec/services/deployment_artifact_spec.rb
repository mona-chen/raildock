require "rails_helper"

RSpec.describe DeploymentArtifact do
  let(:service) { create(:service, config: { "rollbackRetention" => 1 }) }
  let(:deployment) { create(:deployment, service: service, started_at: Time.current) }
  let(:host) { instance_double(HostEngine) }
  let(:image_id) { "sha256:#{'a' * 64}" }
  let(:derived_id) { "sha256:#{'c' * 64}" }
  let(:container_id) { "d" * 64 }
  subject(:artifact) { described_class.new(deployment, host) }

  it "refuses rollback when a retained tag now identifies a different image" do
    deployment.update!(artifact_image_id: image_id, artifact_image_ref: "raildock-history/app:1")
    expect(host).to receive(:run).with("docker image inspect --format '{{.Id}}' raildock-history/app:1").and_return(success: true, output: "sha256:#{'b' * 64}\n")
    expect(artifact.available?).to be false
  end

  it "retains the current image and removes only older retention tags" do
    older = create(:deployment, service: service, artifact_image_id: derived_id, artifact_image_ref: "raildock-history/app:old")
    deployment # Ensure this record has the newer id.
    allow(host).to receive(:dokku_container_name).and_return("app.web.1")
    allow(host).to receive(:run).with("docker inspect --format '{{.Image}}' app.web.1").and_return(success: true, output: image_id)
    allow(host).to receive(:run).with("docker create #{image_id}").and_return(success: true, output: "#{container_id}\n")
    allow(host).to receive(:run).with(a_string_matching(/\Adocker commit --change .* #{container_id} raildock-history\/#{Regexp.escape(service.dokku_app_name)}:#{deployment.id}\z/))
      .and_return(success: true, output: derived_id)
    allow(host).to receive(:run).with("docker image inspect --format '{{.Id}}' raildock-history/#{service.dokku_app_name}:#{deployment.id}")
      .and_return(success: true, output: "#{derived_id}\n")
    allow(host).to receive(:run).with("docker rm --force #{container_id}").and_return(success: true)
    expect(host).to receive(:run).with("docker image rm raildock-history/app:old").and_return(success: true)
    expect(artifact.capture).to be true
    expect(deployment.reload.artifact_image_id).to eq(derived_id)
    expect(deployment.artifact_image_ref).to eq("raildock-history/#{service.dokku_app_name}:#{deployment.id}")
    expect(older.reload.artifact_image_ref).to be_nil
  end

  it "cleans up the temporary container when the relabeled copy cannot be created" do
    allow(host).to receive(:dokku_container_name).and_return("app.web.1")
    allow(host).to receive(:run).with("docker inspect --format '{{.Image}}' app.web.1").and_return(success: true, output: image_id)
    allow(host).to receive(:run).with("docker create #{image_id}").and_return(success: true, output: "#{container_id}\n")
    allow(host).to receive(:run).with(/^docker commit/).and_return(success: false, output: "no space")
    expect(host).to receive(:run).with("docker rm --force #{container_id}").and_return(success: true)

    expect(artifact.capture).to be false
    expect(deployment.reload.artifact_image_ref).to be_nil
  end

  it "forgets a retained tag that a host cleanup already removed" do
    older = create(:deployment, service: service, artifact_image_id: derived_id, artifact_image_ref: "raildock-history/app:gone")
    deployment
    allow(host).to receive(:dokku_container_name).and_return("app.web.1")
    allow(host).to receive(:run).with("docker inspect --format '{{.Image}}' app.web.1").and_return(success: true, output: image_id)
    allow(host).to receive(:run).with("docker create #{image_id}").and_return(success: true, output: "#{container_id}\n")
    allow(host).to receive(:run).with(a_string_matching(/^docker commit/)).and_return(success: true, output: derived_id)
    allow(host).to receive(:run).with(a_string_matching(/^docker image inspect/)).and_return(success: true, output: "#{derived_id}\n")
    allow(host).to receive(:run).with("docker rm --force #{container_id}").and_return(success: true)
    allow(host).to receive(:run).with("docker image rm raildock-history/app:gone").and_return(success: false, output: "Error: No such image: raildock-history/app:gone")

    expect(artifact.capture).to be true
    expect(older.reload.artifact_image_ref).to be_nil
  end
end
