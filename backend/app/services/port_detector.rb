class PortDetector
  def initialize(engine)
    @engine = engine
  end

  # Detect the port an app listens on by inspecting the Docker container/image.
  # Returns the port number or nil if detection fails.
  def detect(service)
    app_name = service.dokku_app_name

    # Try 1: Check if container is running and inspect ExposedPorts
    result = @engine.run("docker inspect --format='{{json .Config.ExposedPorts}}' #{app_name}.web.1 2>/dev/null || true")
    if result[:success] && result[:output].present? && result[:output] != "null" && result[:output] != "{}"
      ports = JSON.parse(result[:output]) rescue nil
      if ports&.keys&.any?
        port = ports.keys.first.split('/').first.to_i
        return port if port > 0
      end
    end

    # Try 2: Check Dockerfile/image metadata via dokku
    result = @engine.run("docker inspect --format='{{json .Config.ExposedPorts}}' dokku/#{app_name}:latest 2>/dev/null || true")
    if result[:success] && result[:output].present? && result[:output] != "null" && result[:output] != "{}"
      ports = JSON.parse(result[:output]) rescue nil
      if ports&.keys&.any?
        port = ports.keys.first.split('/').first.to_i
        return port if port > 0
      end
    end

    # Try 3: Check if the image has EXPOSE directives from the original image
    if service.docker_image.present?
      result = @engine.run("docker inspect --format='{{json .Config.ExposedPorts}}' #{service.docker_image} 2>/dev/null || true")
      if result[:success] && result[:output].present? && result[:output] != "null" && result[:output] != "{}"
        ports = JSON.parse(result[:output]) rescue nil
        if ports&.keys&.any?
          port = ports.keys.first.split('/').first.to_i
          return port if port > 0
        end
      end
    end

    # Try 4: Default based on app type
    # Docker image apps typically listen on 80, 3000, 8080, etc.
    # Buildpack apps default to 5000 (Dokku default)
    service.docker_image.present? ? 80 : 5000
  rescue => e
    Rails.logger.error "Port detection failed for #{app_name}: #{e.message}"
    nil
  end
end
