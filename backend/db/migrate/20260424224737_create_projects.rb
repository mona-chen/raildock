class CreateProjects < ActiveRecord::Migration[8.1]
  def change
    create_table :projects do |t|
      t.string :name
      t.string :description
      t.string :environment
      t.references :server, null: false, foreign_key: true

      t.timestamps
    end
  end
end
