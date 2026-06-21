module Api
  class InvitationsController < BaseController
    skip_before_action :authenticate_user!, raise: false

    def show
      invitation = OrganizationInvitation.find_by(token: params[:token])
      unless invitation
        return render json: { error: "Invitation not found" }, status: :not_found
      end

      if invitation.accepted?
        return render json: { error: "Invitation already accepted" }, status: :gone
      end

      if invitation.expired?
        return render json: { error: "Invitation has expired" }, status: :gone
      end

      existing_user = User.find_by("LOWER(email) = ?", invitation.email.downcase)
      render json: {
        invitation: {
          email: invitation.email,
          role: invitation.role,
          organization: {
            id: invitation.organization.id,
            name: invitation.organization.name,
            slug: invitation.organization.slug
          },
          invited_by: {
            name: invitation.invited_by.name,
            email: invitation.invited_by.email
          },
          expires_at: invitation.expires_at,
          existing_user: existing_user.present?
        }
      }
    end

    def accept
      invitation = OrganizationInvitation.find_by(token: params[:token])
      unless invitation
        return render json: { error: "Invitation not found" }, status: :not_found
      end

      if invitation.accepted?
        return render json: { error: "Invitation already accepted" }, status: :gone
      end

      if invitation.expired?
        return render json: { error: "Invitation has expired" }, status: :gone
      end

      user = User.find_by("LOWER(email) = ?", invitation.email.downcase)
      is_new_account = user.nil?

      if is_new_account
        name  = params[:name].to_s.strip
        password = params[:password].to_s

        if name.blank?
          return render json: { error: "Name is required" }, status: :unprocessable_entity
        end
        if password.length < 8
          return render json: { error: "Password must be at least 8 characters" },
                        status: :unprocessable_entity
        end

        user = User.new(
          email: invitation.email,
          name: name,
          password: password
        )
        unless user.save
          return render json: { error: user.errors.full_messages.join(", ") },
                        status: :unprocessable_entity
        end
      else
        password = params[:password].to_s
        if password.blank? || !user.authenticate(password)
          return render json: { error: "Invalid password" }, status: :unauthorized
        end
      end

      OrganizationMembership.create!(
        user: user,
        organization: invitation.organization,
        role: invitation.role
      )

      invitation.update!(accepted_at: Time.current, user: user)

      render json: {
        token: user.generate_jwt,
        user: user.as_json(only: [ :id, :email, :name, :admin ]),
        organization: {
          id: invitation.organization.id,
          name: invitation.organization.name,
          slug: invitation.organization.slug,
          role: invitation.role
        },
        new_account: is_new_account
      }
    rescue ActiveRecord::RecordNotUnique
      render json: { error: "You are already a member of this organization" },
             status: :unprocessable_entity
    end
  end
end