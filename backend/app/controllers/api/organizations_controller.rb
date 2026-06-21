module Api
  class OrganizationsController < BaseController
    before_action :set_organization, only: [ :show, :update, :destroy ]

    def index
      organizations = current_user.organizations.includes(:owner, :memberships).order(:name)
      render json: organizations.map { |org| serialize(org) }
    end

    def show
      authorize_organization_access!(@organization)
      return if performed?
      render json: serialize(@organization)
    end

    def create
      organization = Organization.new(organization_params)
      organization.owner = current_user

      if organization.save
        # Owner automatically becomes a member with owner role
        OrganizationMembership.create!(user: current_user, organization: organization, role: :owner)
        render json: serialize(organization), status: :created
      else
        render json: { errors: organization.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def update
      authorize_organization_access!(@organization)
      return if performed?

      # Only owners and admins can update
      unless current_user_membership&.admin? || current_user_membership&.owner?
        return render json: { error: "Forbidden" }, status: :forbidden
      end

      if @organization.update(organization_params)
        render json: serialize(@organization)
      else
        render json: { errors: @organization.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def destroy
      authorize_organization_access!(@organization)
      return if performed?

      unless current_user_membership&.owner?
        return render json: { error: "Only owners can delete organizations" }, status: :forbidden
      end

      @organization.destroy
      head :no_content
    end

    private

    def set_organization
      @organization = Organization.find(params[:id])
    end

    def organization_params
      params.require(:organization).permit(:name, :slug, :avatar_url)
    end

    def current_user_membership
      @current_user_membership ||= @organization.memberships.find_by(user: current_user)
    end

    def serialize(org)
      membership = current_user_membership_for(org)
      {
        id: org.id,
        name: org.name,
        slug: org.slug,
        avatar_url: org.avatar_url,
        owner_id: org.owner_id,
        member_count: org.memberships.size,
        role: membership&.role,
        created_at: org.created_at,
        owner: org.owner.as_json(only: [ :id, :name, :email ])
      }
    end

    def current_user_membership_for(org)
      return @current_user_membership if org == @organization && @current_user_membership
      org.memberships.find_by(user: current_user)
    end
  end
end
