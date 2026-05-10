class CreateServiceLinks < ActiveRecord::Migration[8.1]
  def change
    create_table :service_links do |t|
      t.references :from_service, null: false, foreign_key: { to_table: :services }
      t.references :to_service, null: false, foreign_key: { to_table: :services }

      t.timestamps
    end

    add_index :service_links, [:from_service_id, :to_service_id], unique: true
  end
end
