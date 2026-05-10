class CreateDeployments < ActiveRecord::Migration[8.1]
  def change
    create_table :deployments do |t|
      t.references :service, null: false, foreign_key: true
      t.string :status
      t.string :commit_sha
      t.string :commit_message
      t.string :builder
      t.text :build_log
      t.text :deploy_log
      t.datetime :started_at
      t.datetime :completed_at

      t.timestamps
    end
  end
end
