class CreateBackupCopies < ActiveRecord::Migration[8.1]
  def change
    create_table :backup_copies do |t|
      t.references :backup, null: false, foreign_key: true
      t.references :backup_destination, null: true, foreign_key: true
      t.string :kind, null: false, default: "local"
      t.string :storage_key
      t.bigint :size, null: false, default: 0
      t.string :status, null: false, default: "pending"
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :backup_copies, [ :backup_id, :backup_destination_id ], unique: true, where: "backup_destination_id IS NOT NULL", name: "index_backup_copies_on_backup_and_destination"
  end
end
