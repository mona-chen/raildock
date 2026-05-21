# Migration to add ssh_user column to servers table
class AddSshUserToServers < ActiveRecord::Migration[8.1]
  def change
    add_column :servers, :ssh_user, :string, default: "dokku" unless column_exists?(:servers, :ssh_user)
  end
end