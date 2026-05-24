class AddNetworkNameToProjects < ActiveRecord::Migration[8.1]
  def up
    add_column :projects, :network_name, :string

    # Backfill existing projects with their current auto-generated network name
    Project.reset_column_information
    Project.find_each do |project|
      project.update_column(:network_name, "raildock-#{project.id}")
    end
  end

  def down
    remove_column :projects, :network_name
  end
end
