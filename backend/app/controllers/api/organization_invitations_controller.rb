module Api
  class OrganizationInvitationsController < BaseController
    before_action :set_organization
    before_action :authorize_action!

    def index
      invitations = @organization.invitations
        .where(accepted_at: nil)
        .order(created_at: :desc)
      render json: invitations.as_json(include: { invited_by: { only: [ :id, :name, :email ] } })
    end

    def create
      email = params[:email].to_s.downcase.strip
      role  = params[:role].presence || "member"

      unless OrganizationInvitation::ROLES.include?(role)
        return render json: { error: "Invalid role" }, status: :unprocessable_entity
      end

      existing_user = User.find_by("LOWER(email) = ?", email)
      if existing_user && @organization.users.include?(existing_user)
        return render json: { error: "User is already a member of this organization" },
                      status: :unprocessable_entity
      end

      invitation = OrganizationInvitation.new(
        organization: @organization,
        invited_by: current_user,
        email: email,
        role: role
      )

      if existing_user
        invitation.user = existing_user
      end

      if invitation.save
        deliver_invitation(invitation, existing_user)
        render json: invitation_payload(invitation, existing_user: existing_user),
               status: :created
      else
        render json: { error: invitation.errors.full_messages.join(", ") },
               status: :unprocessable_entity
      end
    end

    def destroy
      invitation = @organization.invitations.find(params[:id])
      invitation.destroy
      head :no_content
    end

    private

    def set_organization
      @organization = Organization.find(params[:organization_id])
    end

    def authorize_action!
      authorize_organization_access!(@organization)
      return if performed?

      unless current_user_membership&.admin? || current_user_membership&.owner?
        render json: { error: "Admin access required" }, status: :forbidden
      end
    end

    def current_user_membership
      @current_user_membership ||= @organization.memberships.find_by(user: current_user)
    end

    def deliver_invitation(invitation, existing_user)
      OrganizationMailer.invitation_email(invitation).deliver_later
      Rails.logger.info(
        "[Invitation] #{invitation.email} invited to org=#{@organization.id} " \
        "by user=#{current_user.id} role=#{invitation.role} existing=#{existing_user.present?}"
      )
    rescue => e
      Rails.logger.error("[Invitation] Failed to enqueue mailer: #{e.message}")
    end

    def invitation_payload(invitation, existing_user:)
      base = invitation.as_json(include: { invited_by: { only: [ :id, :name, :email ] } })
      base.merge(
        "accept_url" => accept_url_for(invitation),
        "existing_user" => existing_user.present?
      )
    end

    def accept_url_for(invitation)
      base = Rails.application.config.x.app_url.presence ||
        "#{request.protocol}#{request.host_with_port}"
      "#{base}/invitations/#{invitation.token}"
    end
  end
end
