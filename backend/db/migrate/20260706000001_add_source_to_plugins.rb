class AddSourceToPlugins < ActiveRecord::Migration[8.1]
  def change
    add_column :plugins, :source_type, :string
    add_column :plugins, :source_url, :text
    add_column :plugins, :source_ref, :string
    add_column :plugins, :install_command, :text
    add_column :plugins, :uninstall_command, :text

    add_index :plugins, :source_type
  end
end
