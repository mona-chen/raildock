class CreatePluginSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :plugin_settings do |t|
      t.references :plugin, null: false, foreign_key: true
      t.string :key, null: false
      t.text :value
      t.text :encrypted_value_ciphertext

      t.timestamps
    end

    add_index :plugin_settings, [:plugin_id, :key], unique: true
  end
end
