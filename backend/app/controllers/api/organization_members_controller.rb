module Api
  class OrganizationMembersController < BaseController
    before_action :set_organization
    before_action :set_membership, only: [ :update, :destroy ]
    before_action :require_admin!, only: [ :create, :update ]

    def index
      authorize_organization_access!(@organization)
      return if performed?
      memberships = @organization.memberships.includes(:user).order(:created_at)
      render json: memberships.map { |m| serialize(m) }
    end

    def create
      email = params[:email].to_s.downcase.strip
      user = User.find_by("LOWER(email) = ?", email)

      # If the user does not exist yet, create an invitation instead so admins
      # can onboard teammates without leaving the app.
      unless user
        invitation = OrganizationInvitation.new(
          organization: @organization,
          invited_by: current_user,
          email: email,
          role: params[:role].presence || "member"
        )
        if invitation.save
          OrganizationMailer.invitation_email(invitation).deliver_later
          render json: {
            invitation: invitation.as_json(include: { invited_by: { only: [ :id, :name, :email ] } }),
            accept_url: accept_url_for(invitation),
            existing_user: false
          }, status: :created
        else
          render json: { error: invitation.errors.full_messages.join(", ") },
                 status: :unprocessable_entity
        end
        return
      end

      if @organization.users.include?(user)
        return render json: { error: "User is already a member" }, status: :unprocessable_entity
      end

      membership = OrganizationMembership.create!(
        user: user,
        organization: @organization,
        role: params[:role] || "member"
      )

      render json: serialize(membership), status: :created
    end

    def update
      unless @membership
        return render json: { error: "Membership not found" }, status: :not_found
      end

      # Cannot change owner's role unless you're the owner
      if @membership.owner? && !current_membership.owner?
        return render json: { error: "Only owners can change owner roles" }, status: :forbidden
      end

      # Cannot promote someone to owner unless you're an owner
      if params[:role] == "owner" && !current_membership.owner?
        return render json: { error: "Only owners can promote to owner" }, status: :forbidden
      end

      # Organizations must always have at least one owner
      if @membership.owner? && params[:role].present? && params[:role] != "owner" &&
         @organization.memberships.where(role: :owner).count <= 1
        return render json: { error: "Cannot demote the last owner" }, status: :unprocessable_entity
      end

      if @membership.update(role: params[:role])
        render json: serialize(@membership)
      else
        render json: { errors: @membership.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def destroy
      unless @membership
        return render json: { error: "Membership not found" }, status: :not_found
      end

      # Cannot remove owner
      if @membership.owner?
        return render json: { error: "Cannot remove organization owner" }, status: :forbidden
      end

      # Members can only remove themselves; admins can remove members
      if @membership.user != current_user && !current_membership.admin? && !current_membership.owner?
        return render json: { error: "Forbidden" }, status: :forbidden
      end

      @membership.destroy
      head :no_content
    end

    private

    def set_organization
      @organization = Organization.find(params[:organization_id])
    end

    def set_membership
      @membership = @organization.memberships.find_by(user_id: params[:id])
    end

    def require_admin!
      authorize_organization_access!(@organization)
      return if performed?
      unless current_membership&.admin? || current_membership&.owner?
        render json: { error: "Admin access required" }, status: :forbidden
      end
    end

    def current_membership
      @current_membership ||= @organization.memberships.find_by(user: current_user)
    end

    def serialize(membership)
      {
        id: membership.id,
        userId: membership.user_id,
        role: membership.role,
        user: membership.user.as_json(only: [ :id, :name, :email ]),
        createdAt: membership.created_at,
        isYou: membership.user_id == current_user.id
      }
    end

    def accept_url_for(invitation)
      base = Rails.application.config.x.app_url.presence ||
        "#{request.protocol}#{request.host_with_port}"
      "#{base}/invitations/#{invitation.token}"
    end
  end
end
