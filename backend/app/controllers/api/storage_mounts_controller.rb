module Api
  class StorageMountsController < BaseController
    before_action :set_service

    def create
      mount = @service.storage_mounts.create!(mount_params)

      # Sync to Dokku
      sync_to_dokku(:mount, mount.host_path, mount.container_path)

      render json: mount, status: :created
    end

    def destroy
      mount = @service.storage_mounts.find_by!(host_path: params[:host_path])

      # Sync to Dokku
      sync_to_dokku(:unmount, mount.host_path, mount.container_path)

      mount.destroy!
      head :no_content
    end

    private

    def set_service
      @service = Service.find(params[:service_id])
    end

    def mount_params
      params.permit(:host_path, :container_path)
    end

    def sync_to_dokku(action, host_path, container_path)
      return unless @service.project&.server&.ssh_key.present?

      engine = DokkuEngine.new(@service.project.server)
      if action == :mount
        engine.storage_mount(@service.dokku_app_name, host_path, container_path)
      else
        engine.storage_unmount(@service.dokku_app_name, host_path, container_path)
      end
    end
  end
end
