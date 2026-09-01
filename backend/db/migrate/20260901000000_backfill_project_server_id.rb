# frozen_string_literal: true

class BackfillProjectServerId < ActiveRecord::Migration[7.2]
  def up
    # Backfill projects that have a null server_id by assigning them to the
    # first server belonging to the same user/organization.
    Project.where(server_id: nil).find_each do |project|
      server = Server.where(user_id: project.user_id).first ||
               Server.where(organization_id: project.organization_id).first ||
               Server.first
      project.update_column(:server_id, server&.id) if server
    end
  end

  def down
    # No reverse — the column was already nullable.
  end
end
