module Api
  class DomainsController < BaseController
    before_action :set_service

    def create
      domain = @service.domains.create!(domain_params)

      # Sync to Dokku
      sync_to_dokku(:add, domain.hostname)

      render json: domain, status: :created
    end

    def destroy
      domain = @service.domains.find_by!(hostname: params[:hostname])

      # Sync to Dokku
      sync_to_dokku(:remove, domain.hostname)

      domain.destroy!
      head :no_content
    end

    private

    def set_service
      @service = Service.find(params[:service_id])
    end

    def domain_params
      params.permit(:hostname, :port, :ssl, :letsencrypt)
    end

    def sync_to_dokku(action, hostname)
      return unless @service.project&.server&.ssh_key.present?

      engine = DokkuEngine.new(@service.project.server)
      if action == :add
        engine.domain_add(@service.dokku_app_name, hostname)
      else
        engine.domain_remove(@service.dokku_app_name, hostname)
      end
    end
  end
end
