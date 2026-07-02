class AddMetadataToBackupSchedules < ActiveRecord::Migration[8.1]
  def change
    add_column :backup_schedules, :metadata, :jsonb, default: {}
  end
end
