class AddBaseDomainToServers < ActiveRecord::Migration[8.1]
  def change
    add_column :servers, :base_domain, :string
    add_column :servers, :auto_domains, :boolean, default: true, null: false
  end
end
