module Api
  class DeployKeysController < BaseController
    def index
      if params[:organization_id]
        org = Organization.find(params[:organization_id])
        authorize_organization_access!(org)
        keys = org.deploy_keys
      else
        keys = DeployKey.where(user_id: current_user.id)
                         .or(DeployKey.where(organization_id: current_user.organization_ids))
      end
      render json: keys.as_json(except: [ :private_key_ciphertext ])
    end

    def create
      key_data = SshKeyService.generate(name: deploy_key_params[:name])

      key = DeployKey.new(deploy_key_params.merge(
        public_key: key_data[:public_key],
        private_key: key_data[:private_key],
        fingerprint: key_data[:fingerprint]
      ))

      if params[:organization_id]
        org = Organization.find(params[:organization_id])
        authorize_organization_access!(org)
        key.organization = org
      else
        key.user = current_user
      end

      if key.save
        render json: key.as_json(except: [ :private_key_ciphertext ]), status: :created
      else
        render json: { errors: key.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def destroy
      key = DeployKey.find(params[:id])

      if key.organization
        authorize_organization_access!(key.organization)
      elsif key.user && key.user != current_user
        return render json: { error: "Forbidden" }, status: :forbidden
      end

      key.destroy
      head :no_content
    rescue ActiveRecord::RecordNotFound
      head :not_found
    end

    private

    def deploy_key_params
      params.permit(:name, :git_source_id)
    end
  end
end
