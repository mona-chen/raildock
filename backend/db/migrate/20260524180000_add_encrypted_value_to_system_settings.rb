class AddEncryptedValueToSystemSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :system_settings, :encrypted_value, :text
  end
end
