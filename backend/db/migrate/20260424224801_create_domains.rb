class CreateDomains < ActiveRecord::Migration[8.1]
  def change
    create_table :domains do |t|
      t.references :service, null: false, foreign_key: true
      t.string :hostname
      t.integer :port
      t.boolean :ssl
      t.boolean :letsencrypt

      t.timestamps
    end
  end
end
