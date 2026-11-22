class CreatePitrRestores < ActiveRecord::Migration[8.1]
  def change
    create_table :pitr_restores do |t|
      # The source is only read (its archived base backup + WAL); the restore
      # always lands in a new service so live data is never overwritten.
      t.references :source_service, null: true, index: false, foreign_key: { to_table: :services, on_delete: :nullify }
      t.references :restored_service, null: true, foreign_key: { to_table: :services, on_delete: :nullify }
      t.references :backup, null: true, foreign_key: { on_delete: :nullify }
      t.references :project, null: false, foreign_key: true
      t.datetime :target_time, null: false
      t.string :service_name, null: false
      t.string :status, null: false, default: "pending"
      t.string :isolated_resource_name
      t.text :log
      t.jsonb :metadata, null: false, default: {}
      t.datetime :started_at
      t.datetime :completed_at
      t.timestamps
    end
    add_index :pitr_restores, [ :source_service_id, :created_at ]
  end
end
