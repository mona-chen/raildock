class CreateBackupSchedules < ActiveRecord::Migration[8.1]
  def change
    create_table :backup_schedules do |t|
      t.references :service, null: false, foreign_key: true
      t.string :frequency
      t.integer :retention_count
      t.datetime :last_run_at
      t.datetime :next_run_at

      t.timestamps
    end
  end
end
