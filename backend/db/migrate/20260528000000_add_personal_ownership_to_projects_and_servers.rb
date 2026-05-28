class AddPersonalOwnershipToProjectsAndServers < ActiveRecord::Migration[8.1]
  def change
    add_reference :projects, :user, foreign_key: true, index: true
    add_reference :servers, :user, foreign_key: true, index: true

    change_column_default :users, :admin, from: nil, to: false
    change_column_null :users, :admin, false, false
  end
end
