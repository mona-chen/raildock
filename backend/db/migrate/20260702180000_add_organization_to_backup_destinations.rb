class AddOrganizationToBackupDestinations < ActiveRecord::Migration[8.1]
  def change
    add_reference :backup_destinations, :organization, foreign_key: true, null: true
    add_index :backup_destinations, [ :organization_id, :name ], unique: true, where: "organization_id IS NOT NULL"

    reversible do |dir|
      dir.up do
        execute <<~SQL.squish
          UPDATE backup_destinations
          SET organization_id = servers.organization_id
          FROM servers
          WHERE backup_destinations.server_id = servers.id
            AND servers.organization_id IS NOT NULL
        SQL
      end
    end
  end
end
