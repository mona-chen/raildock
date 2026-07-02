module Api
  class StorageMountsController < BaseController
    include Authorizable
    before_action :set_and_authorize_service!

    def create
      attrs = mount_params.to_h
      attrs[:host_path] ||= auto_host_path(attrs[:kind], attrs[:container_path])

      mount = @service.storage_mounts.build(attrs)
      mount.validate!

      result = sync_to_dokku(:mount, mount.host_path, mount.container_path)
      return render json: { error: result[:output] }, status: :unprocessable_entity if result && !result[:success]

      mount.save!
      sync_storage_env_vars!

      render json: mount, status: :created
    end

    def destroy
      mount = @service.storage_mounts.find_by!(host_path: params[:host_path])

      # Sync to Dokku
      result = sync_to_dokku(:unmount, mount.host_path, mount.container_path)
      return render json: { error: result[:output] }, status: :unprocessable_entity if result && !result[:success]

      mount.destroy!
      sync_storage_env_vars!
      head :no_content
    end

    def browse
      mount = @service.storage_mounts.find(params[:id])
      relative = safe_relative_path(params[:path])

      result = HostEngine.new(@service.project.server).volume_list_directory(mount.host_path, relative)
      return render json: { error: result[:output] }, status: :unprocessable_entity if !result[:success]

      render json: { entries: result[:entries], path: relative, mount: mount.container_path }
    end

    private

    def set_and_authorize_service!
      @service = Service.find(params[:service_id])
      authorize_service!(@service)
    end

    def mount_params
      params.permit(:host_path, :container_path, :kind)
    end

    def auto_host_path(kind, container_path)
      return nil if kind == "bind" || container_path.blank?

      suffix = container_path
        .sub(/\A\//, "")
        .gsub(/[^a-zA-Z0-9_.-]+/, "-")
        .gsub(/\A-+|-+\z/, "")
        .downcase
      suffix = "data" if suffix.blank?

      "#{@service.dokku_app_name}-#{suffix}"
    end

    def sync_to_dokku(action, host_path, container_path)
      return unless @service.project&.server&.ssh_key.present?

      engine = DokkuEngine.new(@service.project.server)
      if action == :mount
        engine.storage_mount(@service.dokku_app_name, host_path, container_path)
      else
        engine.storage_unmount(@service.dokku_app_name, host_path, container_path: container_path)
      end
    end

    def sync_storage_env_vars!
      return unless @service.project&.server&.ssh_key.present?

      StorageMountEnvSync.new(@service, DokkuEngine.new(@service.project.server)).sync!
    end

    def safe_relative_path(value)
      return "/" if value.blank?

      path = value.to_s.gsub("\\", "/").split("/").reject { |part| part.blank? || part == ".." || part == "." }.join("/")
      path.start_with?("/") ? path : "/#{path}"
    end
  end
end
