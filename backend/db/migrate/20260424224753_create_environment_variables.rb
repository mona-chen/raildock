class CreateEnvironmentVariables < ActiveRecord::Migration[8.1]
  def change
    create_table :environment_variables do |t|
      t.references :service, null: false, foreign_key: true
      t.string :key
      t.text :value
      t.string :source
      t.boolean :is_dokku_internal

      t.timestamps
    end
  end
end
