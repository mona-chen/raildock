module Api
  class DatabaseViewerController < BaseController
    include Authorizable

    before_action :set_and_authorize_service!

    # GET /api/services/:service_id/data
    def tables
      viewer = build_viewer
      return unsupported unless viewer

      render json: { success: true, type: @service.subtype, tables: viewer.tables }
    rescue DatabaseViewer::Auth => e
      render_auth_drift(e.message)
    rescue DatabaseViewer::Error => e
      render_error(e.message)
    end

    # GET /api/services/:service_id/data/:table
    def rows
      viewer = build_viewer
      return unsupported unless viewer

      result = viewer.rows(params[:table], limit: params[:limit], offset: params[:offset])
      render json: { success: true }.merge(result)
    rescue DatabaseViewer::Auth => e
      render_auth_drift(e.message)
    rescue DatabaseViewer::Error => e
      render_error(e.message)
    end

    private

    def set_and_authorize_service!
      @service = Service.find(params[:service_id])
      authorize_service!(@service)
    end

    def build_viewer
      return nil unless @service.project&.server&.ssh_key.present?

      viewer = DatabaseViewer.new(@service, DokkuEngine.new(@service.project.server))
      viewer.supported? ? viewer : nil
    end

    def unsupported
      render json: { success: false, error: "Database viewer is not supported for this service" }, status: :unprocessable_entity
    end

    def render_error(message)
      render json: { success: false, error: message }, status: :unprocessable_entity
    end

    # Credentials no longer match the live database. Distinct code + status so
    # the client can surface a clear "creds out of sync / needs resync" state
    # instead of an endless retry spinner.
    def render_auth_drift(message)
      render json: {
        success: false,
        code: "auth_drift",
        error: message,
        actionable: true
      }, status: :service_unavailable
    end
  end
end
