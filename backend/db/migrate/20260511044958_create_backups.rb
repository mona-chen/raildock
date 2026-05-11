class CreateBackups < ActiveRecord::Migration[8.1]
  def change
    create_table :backups do |t|
      t.references :service, null: false, foreign_key: true
      t.string :status
      t.integer :size
      t.string :file_path
      t.jsonb :metadata

      t.timestamps
    end
  end
end
