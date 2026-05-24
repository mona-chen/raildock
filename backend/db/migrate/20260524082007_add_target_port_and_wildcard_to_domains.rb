class AddTargetPortAndWildcardToDomains < ActiveRecord::Migration[8.1]
  def change
    add_column :domains, :target_port, :integer, default: 80
    add_column :domains, :wildcard, :boolean, default: false
  end
end
