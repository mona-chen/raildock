class CreateAdvancedRecovery < ActiveRecord::Migration[8.1]
  def change
    create_table :backup_destinations do |t|
      t.references :server, null: false, foreign_key: true
      t.string :name, null: false
      t.string :provider, null: false, default: "s3"
      t.string :endpoint
      t.string :region, null: false, default: "auto"
      t.string :bucket, null: false
      t.string :path_prefix
      t.text :access_key_id_ciphertext
      t.text :secret_access_key_ciphertext
      t.text :encryption_key_ciphertext
      t.string :status, null: false, default: "pending"
      t.datetime :last_verified_at
      t.text :last_error
      t.timestamps
    end
    add_index :backup_destinations, [ :server_id, :name ], unique: true

    add_reference :backups, :backup_destination, foreign_key: true
    add_column :backups, :backup_kind, :string, null: false, default: "database"
    add_column :backups, :storage_key, :string
    add_column :backups, :encrypted, :boolean, null: false, default: false

    create_table :postgres_pitr_configs do |t|
      t.references :service, null: false, foreign_key: true, index: { unique: true }
      t.references :backup_destination, null: false, foreign_key: true
      t.boolean :enabled, null: false, default: false
      t.integer :retention_days, null: false, default: 7
      t.string :status, null: false, default: "pending"
      t.datetime :last_base_backup_at
      t.datetime :last_wal_archived_at
      t.text :last_error
      t.timestamps
    end

    create_table :restore_drills do |t|
      t.references :backup, null: false, foreign_key: true
      t.string :status, null: false, default: "pending"
      t.string :isolated_resource_name
      t.boolean :checksum_verified, null: false, default: false
      t.text :log
      t.datetime :started_at
      t.datetime :completed_at
      t.timestamps
    end
    add_index :restore_drills, [ :backup_id, :created_at ]
  end
end
