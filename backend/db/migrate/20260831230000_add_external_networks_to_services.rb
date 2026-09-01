# frozen_string_literal: true

class AddExternalNetworksToServices < ActiveRecord::Migration[8.1]
  def change
    add_column :services, :external_networks, :jsonb, default: [], null: false
  end
end
