class CreateStorageMounts < ActiveRecord::Migration[8.1]
  def change
    create_table :storage_mounts do |t|
      t.references :service, null: false, foreign_key: true
      t.string :host_path
      t.string :container_path

      t.timestamps
    end
  end
end
