class CreateServices < ActiveRecord::Migration[8.1]
  def change
    create_table :services do |t|
      t.references :project, null: false, foreign_key: true
      t.string :name
      t.string :service_type
      t.string :subtype
      t.string :status
      t.string :builder
      t.string :git_repo
      t.string :branch
      t.string :last_deployed
      t.string :version
      t.boolean :exposed
      t.integer :port
      t.boolean :locked
      t.string :restart_policy
      t.integer :restart_max_retries
      t.string :dokku_app_name

      t.timestamps
    end
  end
end
