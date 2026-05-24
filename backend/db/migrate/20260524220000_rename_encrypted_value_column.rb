class RenameEncryptedValueColumn < ActiveRecord::Migration[8.1]
  def change
    rename_column :system_settings, :encrypted_value, :encrypted_value_ciphertext
  end
end
