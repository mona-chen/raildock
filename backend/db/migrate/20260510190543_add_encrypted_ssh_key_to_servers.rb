class AddEncryptedSshKeyToServers < ActiveRecord::Migration[8.1]
  def change
    add_column :servers, :ssh_key_ciphertext, :text
  end
end
