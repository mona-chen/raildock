class CreateManifestOperations < ActiveRecord::Migration[8.0]
  def change
    create_table :manifest_operations do |t|
      t.references :project, null: false, foreign_key: true
      t.string :manifest_digest
      t.string :status, null: false, default: "waiting"
      t.jsonb :deployment_ids, null: false, default: []
      t.jsonb :removals, null: false, default: []
      t.boolean :force_destroy_data, null: false, default: false
      t.text :error
      t.datetime :completed_at
      t.timestamps
    end
    add_index :manifest_operations, :status
    add_column :restore_drills, :target_time, :datetime
  end
end
