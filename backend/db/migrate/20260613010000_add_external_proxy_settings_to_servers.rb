class AddExternalProxySettingsToServers < ActiveRecord::Migration[8.1]
  def change
    add_column :servers, :proxy_mode, :string, default: "managed", null: false
    add_column :servers, :external_proxy_network, :string
    add_column :servers, :external_proxy_http_entrypoint, :string, default: "web", null: false
    add_column :servers, :external_proxy_https_entrypoint, :string, default: "websecure", null: false
    add_column :servers, :external_proxy_cert_resolver, :string
    add_column :servers, :external_proxy_redirect_middleware, :string
    add_column :servers, :external_proxy_default_labels, :jsonb, default: {}, null: false
  end
end
