module ApplicationCable
  class Channel < ActionCable::Channel::Base
    private
      def project_accessible?(project, roles: nil)
        return false unless current_user && project
        return true if current_user.admin?
        return project.user_id == current_user.id if project.organization_id.nil?

        membership = current_user.organization_memberships.find_by(organization_id: project.organization_id)
        return false unless membership

        roles.blank? || membership.role.in?(Array(roles).map(&:to_s))
      end
  end
end
