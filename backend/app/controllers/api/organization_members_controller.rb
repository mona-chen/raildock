module Api
  class OrganizationMembersController < BaseController
    before_action :set_organization
    before_action :set_membership, only: [:update, :destroy]
    before_action :require_admin!, only: [:create, :update, :destroy]

    def index
      authorize_organization_access!(@organization)
      memberships = @organization.memberships.includes(:user).order(:created_at)
      render json: memberships.as_json(include: { user: { only: [:id, :name, :email] } })
    end

    def create
      user = User.find_by(email: params[:email])
      unless user
        return render json: { error: "User not found" }, status: :not_found
      end

      if @organization.users.include?(user)
        return render json: { error: "User is already a member" }, status: :unprocessable_entity
      end

      membership = OrganizationMembership.create!(
        user: user,
        organization: @organization,
        role: params[:role] || 'member'
      )

      render json: membership.as_json(include: { user: { only: [:id, :name, :email] } }), status: :created
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
      if params[:role] == 'owner' && !current_membership.owner?
        return render json: { error: "Only owners can promote to owner" }, status: :forbidden
      end

      if @membership.update(role: params[:role])
        render json: @membership.as_json(include: { user: { only: [:id, :name, :email] } })
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
      unless current_membership&.admin? || current_membership&.owner?
        render json: { error: "Admin access required" }, status: :forbidden
      end
    end

    def current_membership
      @current_membership ||= @organization.memberships.find_by(user: current_user)
    end
  end
end
