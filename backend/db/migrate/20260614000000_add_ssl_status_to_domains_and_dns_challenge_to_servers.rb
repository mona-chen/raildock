class AddSslStatusToDomainsAndDnsChallengeToServers < ActiveRecord::Migration[8.1]
  def change
    # SSL status tracking on domains
    add_column :domains, :ssl_status, :string, default: "none", null: false
    add_column :domains, :ssl_status_message, :string
    add_column :domains, :ssl_expires_at, :datetime
    add_column :domains, :ssl_checked_at, :datetime
    add_column :domains, :challenge_type, :string, default: "http", null: false

    add_index :domains, :ssl_status

    # DNS challenge configuration on servers
    add_column :servers, :dns_challenge_provider, :string
    add_column :servers, :dns_challenge_credentials_ciphertext, :text
  end
end
