class CreateDeployKeys < ActiveRecord::Migration[8.1]
  def change
    create_table :deploy_keys do |t|
      t.string :name, null: false
      t.text :public_key
      t.text :private_key_ciphertext
      t.string :fingerprint
      t.references :organization, foreign_key: true, null: true
      t.references :user, foreign_key: true, null: true
      t.references :git_source, foreign_key: true, null: true
      t.datetime :last_used_at
      t.timestamps
    end

    add_index :deploy_keys, :fingerprint
    add_index :deploy_keys, [ :organization_id, :name ], unique: true, where: "organization_id IS NOT NULL"
    add_index :deploy_keys, [ :user_id, :name ], unique: true, where: "user_id IS NOT NULL"
  end
end
