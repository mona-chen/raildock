class CreatePlugins < ActiveRecord::Migration[8.1]
  def change
    create_table :plugins do |t|
      t.string :slug, null: false
      t.string :name, null: false
      t.text :description
      t.string :category, null: false
      t.string :icon
      t.string :status, null: false, default: "built_in"
      t.string :version
      t.jsonb :config_schema, default: {}
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :plugins, :slug, unique: true
    add_index :plugins, :category
    add_index :plugins, :status
  end
end
