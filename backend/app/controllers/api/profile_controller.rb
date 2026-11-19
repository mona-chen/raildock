module Api
  class ProfileController < BaseController
    # Account credentials belong to the person, not to a machine credential.
    # A leaked API token must not be able to change the owner's email or
    # password, even though the token authenticates as that user.
    def update
      if current_api_token
        return render json: {
          error: "API tokens cannot change the account profile",
          code: "token_not_allowed"
        }, status: :forbidden
      end

      user = current_user
      attributes = profile_params
      email = attributes[:email].to_s.strip
      email_changed = email.present? && email != user.email
      password_changed = attributes[:password].present?

      if (email_changed || password_changed) && !user.authenticate(params[:current_password].to_s)
        return render json: {
          error: "Enter your current password to change your email or password",
          code: "current_password_invalid"
        }, status: :unprocessable_entity
      end

      if password_changed && attributes[:password] != params[:password_confirmation].to_s
        return render json: {
          error: "New password and confirmation do not match",
          code: "password_confirmation_mismatch"
        }, status: :unprocessable_entity
      end

      user.name = attributes[:name] if attributes.key?(:name)
      user.email = email if attributes.key?(:email)
      if password_changed
        user.password = attributes[:password]
        user.password_confirmation = params[:password_confirmation]
      end

      if user.save
        render json: user_payload_with_orgs(user)
      else
        render json: {
          error: user.errors.full_messages.join(", "),
          code: "validation_failed"
        }, status: :unprocessable_entity
      end
    end

    private

    def profile_params
      source = params[:user].is_a?(ActionController::Parameters) ? params[:user] : params
      source.permit(:name, :email, :password)
    end
  end
end
