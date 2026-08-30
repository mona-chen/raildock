class AddFrameworkToServices < ActiveRecord::Migration[8.1]
  def change
    add_column :services, :framework, :string
  end
end
