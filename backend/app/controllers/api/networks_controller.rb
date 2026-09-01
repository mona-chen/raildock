module Api
  class NetworksController < BaseController
    include Authorizable

    def index
      server = scoped_servers.find(params[:server_id] || params[:id])
      inventory = network_inventory(server)
      return render_inventory_error(inventory) unless inventory[:success]

      render json: inventory[:networks]
    rescue JSON::ParserError => e
      render json: { error: "Docker returned invalid inventory data", details: e.message }, status: :unprocessable_entity
    end

    def validate
      server = scoped_servers.find(params[:server_id] || params[:id])
      network_name = params[:network].to_s
      return render json: { error: "Network is required" }, status: :unprocessable_entity if network_name.blank?

      inventory = network_inventory(server)
      return render_inventory_error(inventory) unless inventory[:success]

      network = inventory[:networks].find { |candidate| candidate[:name] == network_name }
      unless network&.dig(:selectable)
        return render json: { error: "Network '#{network_name}' is not available for external proxy use" }, status: :unprocessable_entity
      end
      unless network[:recommended]
        return render json: { error: "No Traefik container was found on '#{network_name}'" }, status: :unprocessable_entity
      end

      render json: {
        success: true,
        network: network[:name],
        traefik_containers: network[:traefik_containers]
      }
    rescue JSON::ParserError => e
      render json: { error: "Docker returned invalid inventory data", details: e.message }, status: :unprocessable_entity
    end

    private

    def network_inventory(server)
      host_engine = HostEngine.new(server)
      networks_result = host_engine.docker_network_inventory
      containers_result = host_engine.docker_container_inventory
      unless networks_result[:success] && containers_result[:success]
        return {
          success: false,
          details: networks_result[:output].presence || containers_result[:output]
        }
      end

      containers = parse_json_lines(containers_result[:output])
      traefik_containers = containers.select do |container|
        container["Image"].to_s.downcase.include?("traefik") ||
          container["Names"].to_s.downcase.include?("traefik")
      end

      networks = parse_json_lines(networks_result[:output]).map do |network|
        name = network["Name"].to_s
        connected_names = network.fetch("Containers", {}).values.filter_map { |container| container["Name"] }
        traefik_names = traefik_containers.filter_map do |container|
          container["Names"] if container["Networks"].to_s.split(",").include?(name)
        end

        {
          name: name,
          driver: network["Driver"],
          scope: network["Scope"],
          internal: network["Internal"],
          containers: connected_names,
          traefik_containers: traefik_names,
          recommended: traefik_names.any?,
          selectable: !%w[bridge host none].include?(name),
          connectable: !%w[bridge host none].include?(name)
        }
      end

      {
        success: true,
        networks: networks.sort_by { |network| [ network[:recommended] ? 0 : 1, network[:name] ] }
      }
    end

    def render_inventory_error(inventory)
      render json: {
        error: "Unable to inspect Docker networks",
        details: inventory[:details]
      }, status: :unprocessable_entity
    end

    def parse_json_lines(output)
      output.to_s.each_line.filter_map do |line|
        stripped = line.strip
        JSON.parse(stripped) if stripped.present?
      end
    end
  end
end
