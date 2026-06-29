# Imports existing Docker containers from a host into RailDock as Dokku-managed
# app services. Preserves the container image, environment variables, published
# ports, and bind mounts.
class ContainerImporter
  attr_reader :server, :user, :organization

  def initialize(server, user, organization: nil)
    @server = server
    @user = user
    @organization = organization
  end

  # containers is an array of hashes produced by DockerContainerScanner.
  # project can be an existing Project, or nil to create one named
  # "Imported Containers".
  def import(containers, project: nil)
    project ||= create_project!
    results = containers.map { |attrs| import_container(attrs.with_indifferent_access, project) }

    {
      success: results.all? { |r| r[:success] },
      project_id: project.id,
      project_name: project.name,
      results: results
    }
  rescue => e
    Rails.logger.error "ContainerImporter failed: #{e.message}"
    { success: false, error: e.message, results: [] }
  end

  private

  def create_project!
    Project.create!(
      name: "Imported Containers",
      organization: organization,
      user: organization ? nil : user,
      server: server
    )
  end

  def import_container(attrs, project)
    attrs = attrs.deep_symbolize_keys if attrs.respond_to?(:deep_symbolize_keys)
    original_name = attrs[:name].to_s
    return { success: false, name: original_name, error: "Container name is missing" } if original_name.blank?
    return { success: false, name: original_name, error: "Container image is missing" } if attrs[:image].blank?

    name = unique_name(project, sanitize_name(original_name))
    ports = Array(attrs[:ports])
    port = detect_container_port(ports)

    service = project.services.create!(
      name: name,
      service_type: "app",
      docker_image: attrs[:image],
      status: attrs[:running] ? "running" : "stopped",
      port: port,
      config: default_config(port, ports)
    )

    create_environment_variables(service, attrs[:env] || {})
    create_storage_mounts(service, attrs[:mounts] || [])
    queue_deployment(service)

    {
      success: true,
      service_id: service.id,
      name: service.name,
      image: service.docker_image,
      port: port
    }
  rescue => e
    Rails.logger.error "Failed to import container #{attrs[:name]}: #{e.message}"
    { success: false, name: attrs[:name], error: e.message }
  end

  def unique_name(project, base)
    return base unless project.services.exists?(name: base)

    (2..100).each do |i|
      candidate = "#{base}-#{i}"
      return candidate unless project.services.exists?(name: candidate)
    end
    "#{base}-#{SecureRandom.hex(4)}"
  end

  def sanitize_name(name)
    name.to_s.downcase.gsub(/[^a-z0-9_-]/, "-").gsub(/-+/, "-").gsub(/^-|-$/, "")[0, 40].presence || "imported"
  end

  def detect_container_port(ports)
    # Prefer the first port that is actually published on the host.
    published = ports.find { |p| p[:host_port].present? }
    return published[:container_port].to_i if published

    # Otherwise fall back to the first exposed port.
    ports.first&.dig(:container_port).to_i
  end

  def default_config(port, ports)
    port_mappings = ports.filter_map do |p|
      next unless p[:host_port].present?

      {
        scheme: p[:host_port].to_i == 443 ? "https" : "http",
        hostPort: p[:host_port].to_i,
        containerPort: p[:container_port].to_i
      }
    end

    {
      proxy: {
        enabled: true,
        proxyType: server.default_proxy || "traefik",
        portMappings: port_mappings
      }
    }
  end

  def create_environment_variables(service, env)
    env.each do |key, value|
      next if key.blank?
      next if value.to_s.blank?
      next unless key.match?(/\A[A-Za-z_][A-Za-z0-9_\-\.]*\z/)

      service.environment_variables.create!(
        key: key,
        value: value.to_s,
        source: "imported",
        is_dokku_internal: false
      )
    end
  end

  def create_storage_mounts(service, mounts)
    mounts.each do |m|
      next unless m.is_a?(Hash)
      next unless m[:type] == "bind"
      next if m[:source].blank? || m[:destination].blank?

      service.storage_mounts.create!(
        host_path: m[:source],
        container_path: m[:destination]
      )
    end
  end

  def queue_deployment(service)
    deployment = service.deployments.create!(
      status: :pending,
      started_at: Time.current,
      branch: service.branch || "main",
      commit_message: "Imported from existing Docker container",
      triggered_by: "import"
    )
    DeploymentJob.perform_later(service.id, deployment.id)
    service.update!(status: :deploying)
  end
end
