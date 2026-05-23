class AddManifestSupport < ActiveRecord::Migration[8.1]
  def change
    # Service ownership model
    add_column :services, :managed_by, :string, default: "ui", null: false
    add_index :services, :managed_by

    # Hybrid mode overrides
    add_column :services, :config_overrides, :jsonb, default: {}, null: false

    # Project manifest tracking
    add_column :projects, :manifest_format, :string
    add_column :projects, :manifest_content, :text
    add_column :projects, :manifest_last_synced_at, :datetime
    add_column :projects, :manifest_last_applied_at, :datetime
    add_column :projects, :manifest_drift_detected, :boolean, default: false, null: false

    # Manifest change audit log
    create_table :manifest_changes do |t|
      t.references :project, null: false, foreign_key: true
      t.string :service_name, null: false
      t.string :field, null: false
      t.string :change_type, null: false
      t.jsonb :old_value
      t.jsonb :new_value
      t.string :severity, null: false
      t.string :status, default: "pending", null: false
      t.string :job_id
      t.timestamps
    end

    add_index :manifest_changes, [:project_id, :status]
    add_index :manifest_changes, [:project_id, :service_name]
  end
end
