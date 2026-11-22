module Api
  class BackupDestinationsController < BaseController
    before_action :set_organization
    before_action :require_member!
    before_action :set_destination, only: [ :show, :update, :destroy, :verify ]
    # Verification writes and deletes a probe object in the bucket, so it is a
    # mutating action like the others.
    before_action :require_admin!, only: [ :create, :update, :destroy, :update_defaults, :verify ]

    # Settings that decide where bytes go. A name-only edit does not need a new
    # probe; changing any of these does.
    CONNECTION_ATTRIBUTES = %w[
      provider endpoint region bucket path_prefix access_key_id_ciphertext secret_access_key_ciphertext
    ].freeze

    def index
      destinations = @organization.backup_destinations.order(:name)
      render json: destinations
    end

    def show
      render json: @destination
    end

    # Destinations every service in this organization backs up to unless it has
    # picked its own. Reading is open to members because the service Backup tab
    # renders the inherited choice.
    def defaults
      render json: { default_destination_ids: Array(@organization.default_backup_destination_ids) }
    end

    def update_defaults
      ids = Array(params[:destination_ids]).compact_blank.map(&:to_s)
      unknown = ids - @organization.backup_destinations.ids.map(&:to_s)
      return render json: { error: "Unknown backup destination(s): #{unknown.join(', ')}" }, status: :unprocessable_entity if unknown.any?

      @organization.update!(default_backup_destination_ids: ids)
      render json: { default_destination_ids: Array(@organization.default_backup_destination_ids) }
    end

    # Creation and verification are one unit: the candidate is probed while
    # still unsaved and only persisted once it has proven it can store and
    # serve an object. A failed probe leaves no row behind (so retrying the same
    # name works) and never reveals a recovery key for a destination that does
    # not exist.
    def create
      destination = @organization.backup_destinations.build(destination_params)
      return render_invalid(destination) unless destination.valid?

      generated_key = destination_params[:encryption_key].blank?
      BackupDestinationClient.new(destination, interactive: true).probe!
      destination.assign_attributes(status: "verified", last_verified_at: Time.current, last_error: nil)
      return render_invalid(destination) unless destination.save

      json = destination.as_json
      # A key the operator supplied is already in their hands; only a generated
      # one is shown, exactly once.
      json["recovery_key"] = destination.encryption_key if generated_key
      render json: json, status: :created
    rescue ApplicationController::AuthorizationDenied, ServiceOperationLock::Busy
      raise
    rescue => error
      render json: { error: "Destination verification failed: #{error.message}" }, status: :unprocessable_entity
    end

    # Candidate settings are probed in memory. The stored row changes only when
    # the probe passes, so a typo in a rotated key cannot mark a working
    # destination failed. Blank secrets mean "keep the current one". The
    # recovery key never changes: artifacts already stored depend on it.
    def update
      attributes = destination_params.except(:encryption_key)
      %i[access_key_id secret_access_key].each { |field| attributes.delete(field) if attributes[field].blank? }
      # The edit form resubmits every field; "" for a nil endpoint is not a
      # change and must not trigger a probe.
      attributes = attributes.to_h.reject { |field, value| value.presence == @destination.public_send(field).presence }
      @destination.assign_attributes(attributes)
      return render_invalid(@destination) unless @destination.valid?

      if (@destination.changed & CONNECTION_ATTRIBUTES).any?
        BackupDestinationClient.new(@destination, interactive: true).probe!
        @destination.assign_attributes(status: "verified", last_verified_at: Time.current, last_error: nil)
      end
      return render_invalid(@destination) unless @destination.save

      render json: @destination
    rescue ApplicationController::AuthorizationDenied, ServiceOperationLock::Busy
      raise
    rescue => error
      render json: { error: "Destination verification failed: #{error.message}" }, status: :unprocessable_entity
    end

    def destroy
      # Backups and PITR configs point at this destination; deleting it silently
      # would orphan every artifact stored there.
      if @destination.destroy
        head :no_content
      else
        in_use = {
          backups: @destination.backups.count,
          backup_copies: @destination.backup_copies.count,
          postgres_pitr_configs: @destination.postgres_pitr_configs.count
        }
        render json: { error: in_use_message(in_use), code: "destination_in_use", in_use: in_use },
          status: :unprocessable_entity
      end
    end

    # Re-proves the stored settings. verify! records the outcome (including
    # last_error) on the row itself.
    def verify
      BackupDestinationClient.new(@destination, interactive: true).verify!
      render json: @destination.reload
    rescue ApplicationController::AuthorizationDenied, ServiceOperationLock::Busy
      raise
    rescue => error
      render json: { error: "Destination verification failed: #{error.message}" }, status: :unprocessable_entity
    end

    private

      def in_use_message(in_use)
        parts = []
        parts << "#{in_use[:backups]} backup#{'s' unless in_use[:backups] == 1}" if in_use[:backups].positive?
        parts << "#{in_use[:backup_copies]} backup cop#{in_use[:backup_copies] == 1 ? 'y' : 'ies'}" if in_use[:backup_copies].positive?
        if in_use[:postgres_pitr_configs].positive?
          parts << "#{in_use[:postgres_pitr_configs]} point-in-time recovery configuration#{'s' unless in_use[:postgres_pitr_configs] == 1}"
        end
        return @destination.errors.full_messages.to_sentence if parts.empty?

        "#{@destination.name} still holds #{parts.to_sentence}. Remove or move them before deleting the destination."
      end

      def render_invalid(destination)
        render json: { error: destination.errors.full_messages.to_sentence, errors: destination.errors.to_hash },
          status: :unprocessable_entity
      end

      def set_organization
        @organization = Organization.find(params[:organization_id])
        authorize_organization_access!(@organization)
      end

      def set_destination
        @destination = @organization.backup_destinations.find(params[:id])
      end

      def require_member!
        return if current_user.organizations.include?(@organization)

        render json: { error: "Forbidden" }, status: :forbidden
      end

      def require_admin!
        membership = @organization.memberships.find_by(user: current_user)
        return if membership&.admin? || membership&.owner?

        render json: { error: "Admin access required" }, status: :forbidden
      end

      def destination_params
        params.permit(
          :name, :provider, :endpoint, :region, :bucket, :path_prefix,
          :access_key_id, :secret_access_key, :encryption_key
        )
      end
  end
end
