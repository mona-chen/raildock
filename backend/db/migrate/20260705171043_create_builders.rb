class CreateBuilders < ActiveRecord::Migration[8.1]
  def change
    create_table :builders do |t|
      t.references :plugin, null: false, foreign_key: true
      t.string :slug, null: false
      t.string :name, null: false
      t.text :description
      t.string :dokku_builder, null: false
      t.jsonb :source_types, default: [], null: false
      t.integer :priority, default: 0, null: false
      t.jsonb :language_tags, default: []
      t.string :icon
      t.string :color
      t.jsonb :config_schema, default: {}
      t.jsonb :metadata, default: {}
      t.string :status, default: "built_in", null: false
      t.timestamps
    end

    add_index :builders, :slug, unique: true
    add_index :builders, :status
    add_index :builders, :source_types, using: :gin
  end
end
