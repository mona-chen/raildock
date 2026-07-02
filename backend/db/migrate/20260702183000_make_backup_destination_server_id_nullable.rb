class MakeBackupDestinationServerIdNullable < ActiveRecord::Migration[8.1]
  def change
    change_column_null :backup_destinations, :server_id, true
  end
end
