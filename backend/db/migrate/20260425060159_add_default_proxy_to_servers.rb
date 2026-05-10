class AddDefaultProxyToServers < ActiveRecord::Migration[8.1]
  def change
    add_column :servers, :default_proxy, :string
  end
end
