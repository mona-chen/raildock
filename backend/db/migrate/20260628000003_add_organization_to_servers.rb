class AddOrganizationToServers < ActiveRecord::Migration[8.1]
  def change
    add_reference :servers, :organization, foreign_key: true
  end
end
