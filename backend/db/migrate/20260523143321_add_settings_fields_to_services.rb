class AddSettingsFieldsToServices < ActiveRecord::Migration[8.1]
  def change
    add_column :services, :auto_deploy, :boolean, default: true, null: false
    add_column :services, :root_directory, :string
    add_column :services, :start_command, :string
    add_column :services, :maintenance_mode, :boolean, default: false, null: false
  end
end
