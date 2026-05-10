class CreateServers < ActiveRecord::Migration[8.1]
  def change
    create_table :servers do |t|
      t.string :name
      t.string :host
      t.string :status
      t.string :dokku_version
      t.string :docker_version
      t.string :os
      t.string :uptime
      t.integer :disk_used
      t.integer :disk_total
      t.integer :memory_used
      t.integer :memory_total
      t.text :ssh_key

      t.timestamps
    end
  end
end
