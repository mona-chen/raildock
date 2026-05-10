class CreateProcessTypes < ActiveRecord::Migration[8.1]
  def change
    create_table :process_types do |t|
      t.references :service, null: false, foreign_key: true
      t.string :name
      t.integer :quantity
      t.integer :running
      t.string :command

      t.timestamps
    end
  end
end
