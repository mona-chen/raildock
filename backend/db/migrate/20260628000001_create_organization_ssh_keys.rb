class CreateOrganizationSshKeys < ActiveRecord::Migration[8.1]
  def change
    create_table :organization_ssh_keys do |t|
      t.references :organization, null: false, foreign_key: true, index: { unique: true }
      t.text :private_key_ciphertext, null: false
      t.text :public_key, null: false
      t.string :fingerprint, null: false

      t.timestamps
    end
  end
end
