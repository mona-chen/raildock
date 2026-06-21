class ApplicationController < ActionController::API
  private

  def user_payload_with_orgs(user)
    orgs = user.organizations.includes(:memberships).order(:name).map do |org|
      membership = org.memberships.find { |m| m.user_id == user.id }
      {
        id: org.id,
        name: org.name,
        slug: org.slug,
        role: membership&.role,
        member_count: org.memberships.count
      }
    end

    {
      id: user.id,
      email: user.email,
      name: user.name,
      admin: user.admin?,
      organizations: orgs
    }
  end

  def ensure_personal_organization(user)
    return if user.organizations.any?

    slug_base = user.name.parameterize.presence || user.email.split("@").first
    slug = unique_slug_for(slug_base)

    Organization.transaction do
      organization = Organization.create!(
        name: "#{user.name}'s Workspace",
        slug: slug,
        owner: user
      )
      OrganizationMembership.create!(
        user: user,
        organization: organization,
        role: :owner
      )

      adopt_orphaned_resources(user, organization)

      organization
    end
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "[Org] Failed to create personal org for #{user.email}: #{e.message}"
    nil
  end

  def adopt_orphaned_resources(user, organization)
    user.projects.where(organization_id: nil).update_all(organization_id: organization.id)
    user.deploy_keys.where(organization_id: nil).update_all(organization_id: organization.id)
  end

  def unique_slug_for(base)
    slug = base.to_s.downcase.gsub(/[^a-z0-9-]/, "-").gsub(/-+/, "-").gsub(/^-|-$/, "")
    slug = "workspace" if slug.blank?
    candidate = slug
    suffix = 1
    while Organization.where(slug: candidate).exists?
      suffix += 1
      candidate = "#{slug}-#{suffix}"
    end
    candidate
  end
end