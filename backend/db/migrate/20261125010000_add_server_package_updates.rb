class AddServerPackageUpdates < ActiveRecord::Migration[8.1]
  def change
    add_column :servers, :package_updates, :jsonb, default: {}, null: false
  end
end
