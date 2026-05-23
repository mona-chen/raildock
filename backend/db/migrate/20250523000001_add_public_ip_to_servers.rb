class AddPublicIpToServers < ActiveRecord::Migration[8.1]
  def change
    add_column :servers, :public_ip, :string
  end
end
