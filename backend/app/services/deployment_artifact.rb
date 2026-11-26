require "digest"
require "shellwords"

# Pin a bounded set of local immutable images. Database restores are never part
# of image rollback; the current environment/configuration remains in effect.
class DeploymentArtifact
  def initialize(deployment, host_engine)
    @deployment = deployment
    @service = deployment.service
    @host = host_engine
  end

  def capture(engine: nil)
    container = @host.dokku_container_name(@service.dokku_app_name)
    return false if container.blank?
    result = @host.run("docker inspect --format '{{.Image}}' #{Shellwords.escape(container)}")
    image_id = result[:output].to_s.strip
    return false unless result[:success] && image_id.match?(/\Asha256:[a-f0-9]{64}\z/)
    ref = "raildock-history/#{@service.dokku_app_name}:#{@deployment.id}"
    artifact_image_id = retain(image_id, ref)
    return false unless artifact_image_id
    @deployment.update!(artifact_image_id: artifact_image_id, artifact_image_ref: ref,
      config_revision: Digest::SHA256.hexdigest([ @service.config.to_json, @service.environment_variables.order(:key).pluck(:key, :value).to_json ].join("\n")))
    keep = (@service.config || {}).fetch("rollbackRetention", 3).to_i.clamp(1, 10)
    if engine
      native = engine.builds_list(@service.dokku_app_name)
      if native[:success]
        builds = JSON.parse(native[:output])
        build = builds.select { |row| row["status"] == "succeeded" && Time.iso8601(row["started_at"]) >= @deployment.started_at - 2.seconds }.max_by { |row| row["started_at"] }
        @deployment.update!(native_build_id: build["id"]) if build
      end
    end
    older_ids = @service.deployments.where.not(artifact_image_ref: nil).order(id: :desc).offset(keep).pluck(:id)
    @service.deployments.where(id: older_ids).find_each do |older|
      removed = @host.run("docker image rm #{Shellwords.escape(older.artifact_image_ref)}")
      output = removed[:output].to_s
      older.update!(artifact_image_ref: nil) if removed[:success] || output.match?(/No such image|image not found|not found/i)
    end
    true
  rescue JSON::ParserError, ArgumentError => e
    Rails.logger.warn "Native artifact metadata unavailable: #{e.class}"
    false
  end

  def available?
    return false if @deployment.artifact_image_ref.blank? || @deployment.artifact_image_id.blank?
    result = @host.run("docker image inspect --format '{{.Id}}' #{Shellwords.escape(@deployment.artifact_image_ref)}")
    result[:success] && result[:output].to_s.strip == @deployment.artifact_image_id
  end

  private

  # Dokku's pre-deploy cleanup removes every unused image carrying this app's
  # label, including a plain `docker image tag` of the deployed image. Commit a
  # metadata-only copy under a different app label first: layers and runtime
  # configuration stay identical, but cleanup no longer claims it.
  def retain(image_id, ref)
    created = @host.run("docker create #{Shellwords.escape(image_id)}")
    container_id = created[:output].to_s.strip
    return false unless created[:success] && container_id.match?(/\A[a-f0-9]{12,64}\z/)

    committed = @host.run("docker commit --change #{Shellwords.escape('LABEL com.dokku.app-name=raildock-history')} #{container_id} #{Shellwords.escape(ref)}")
    return false unless committed[:success]

    inspected = @host.run("docker image inspect --format '{{.Id}}' #{Shellwords.escape(ref)}")
    derived_id = inspected[:output].to_s.strip
    return false unless inspected[:success] && derived_id.match?(/\Asha256:[a-f0-9]{64}\z/)

    derived_id
  ensure
    @host.run("docker rm --force #{container_id}") if container_id&.match?(/\A[a-f0-9]{12,64}\z/)
  end
end
