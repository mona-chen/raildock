class AddDetectedPortToServices < ActiveRecord::Migration[8.1]
  def change
    add_column :services, :detected_port, :integer
  end
end
