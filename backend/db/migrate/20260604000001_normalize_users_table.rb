class NormalizeUsersTable < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :email, :string, if_not_exists: true
    add_column :users, :name, :string, if_not_exists: true
    add_column :users, :password_digest, :string, if_not_exists: true
    add_column :users, :admin, :boolean, default: false, null: false, if_not_exists: true

    add_index :users, :email, unique: true, if_not_exists: true
  end
end
