class CreateActivityEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :activity_events do |t|
      t.references :project, null: false, foreign_key: true
      t.string :service_name
      t.string :action
      t.string :message
      t.jsonb :metadata

      t.timestamps
    end
  end
end
