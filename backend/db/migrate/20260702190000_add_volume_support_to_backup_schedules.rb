class AddVolumeSupportToBackupSchedules < ActiveRecord::Migration[8.1]
  def change
    add_column :backup_schedules, :backup_kind, :string, null: false, default: "database"
    add_reference :backup_schedules, :storage_mount, foreign_key: true, null: true

    add_index :backup_schedules, :backup_kind
  end
end
