class ExpandBackupSize < ActiveRecord::Migration[8.1]
  def change
    change_column :backups, :size, :bigint
    add_index :backup_schedules, :next_run_at
  end
end
