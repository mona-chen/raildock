class AddSshPortToServers < ActiveRecord::Migration[8.0]
  def change
    add_column :servers, :ssh_port, :integer, default: 22, null: false
    # Written by ServerHealthCheckJob so the UI can tell a fresh status from a
    # stale one.
    add_column :servers, :status_checked_at, :datetime
    add_column :servers, :status_error, :string
  end
end
