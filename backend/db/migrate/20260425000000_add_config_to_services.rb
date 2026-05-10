class AddConfigToServices < ActiveRecord::Migration[8.1]
  def change
    add_column :services, :config, :jsonb, default: {}
    add_column :projects, :shared_vars, :jsonb, default: []
  end
end
