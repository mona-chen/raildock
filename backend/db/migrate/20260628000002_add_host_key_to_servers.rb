class AddHostKeyToServers < ActiveRecord::Migration[8.1]
  def change
    add_column :servers, :host_key, :text
    add_column :servers, :host_key_fingerprint, :string
  end
end
