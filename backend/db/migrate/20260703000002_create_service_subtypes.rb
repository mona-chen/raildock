class CreateServiceSubtypes < ActiveRecord::Migration[8.1]
  def change
    create_table :service_subtypes do |t|
      t.references :plugin, null: false, foreign_key: true
      t.string :subtype, null: false
      t.string :name, null: false
      t.text :description
      t.string :service_type, null: false
      t.string :dokku_plugin
      t.string :command_namespace
      t.string :default_version
      t.string :icon
      t.string :color
      t.jsonb :capabilities, default: []
      t.jsonb :config_schema, default: {}
      t.string :env_var_prefix
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :service_subtypes, :subtype, unique: true
    add_index :service_subtypes, :service_type
    add_index :service_subtypes, :capabilities, using: :gin
    add_index :service_subtypes, [ :plugin_id, :subtype ], unique: true
  end
end
