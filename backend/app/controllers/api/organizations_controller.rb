module Api
  class OrganizationsController < BaseController
    before_action :set_organization, only: [ :show, :update, :destroy ]

    def index
      organizations = current_user.organizations.includes(:owner).order(:name)
      render json: organizations.as_json(include: { owner: { only: [ :id, :name, :email ] } })
    end

    def show
      authorize_organization_access!(@organization)
      return if performed?
      render json: @organization.as_json(include: { owner: { only: [ :id, :name, :email ] } })
    end

    def create
      organization = Organization.new(organization_params)
      organization.owner = current_user

      if organization.save
        # Owner automatically becomes a member with owner role
        OrganizationMembership.create!(user: current_user, organization: organization, role: :owner)
        render json: organization, status: :created
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
        render json: @organization
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
  end
end
