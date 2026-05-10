class MakeServerIdNullableOnProjects < ActiveRecord::Migration[8.1]
  def change
    change_column_null :projects, :server_id, true
  end
end
