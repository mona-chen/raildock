class AddTemporaryToDomains < ActiveRecord::Migration[8.1]
  def change
    add_column :domains, :temporary, :boolean, default: false, null: false
    add_index :domains, :temporary
  end
end
