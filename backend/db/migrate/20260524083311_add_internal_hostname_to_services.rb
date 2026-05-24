class AddInternalHostnameToServices < ActiveRecord::Migration[8.1]
  def change
    add_column :services, :internal_hostname, :string
  end
end
