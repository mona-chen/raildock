class DropSshKeyFromServers < ActiveRecord::Migration[8.1]
  def change
    remove_column :servers, :ssh_key, :text
  end
end
