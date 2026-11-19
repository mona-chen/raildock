class CreateOperations < ActiveRecord::Migration[8.0]
  def change
    create_table :operations do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :project, foreign_key: { on_delete: :nullify }
      t.references :service, foreign_key: { on_delete: :nullify }
      t.references :api_token, foreign_key: { on_delete: :nullify }
      t.string :kind, null: false
      t.string :subject_type
      t.bigint :subject_id
      t.string :status
      t.string :idempotency_key
      t.string :request_fingerprint
      t.text :error
      t.datetime :completed_at
      t.timestamps
    end

    add_index :operations, [ :organization_id, :idempotency_key ],
      unique: true,
      where: "idempotency_key IS NOT NULL",
      name: "index_operations_on_org_and_idempotency_key"
    add_index :operations, [ :subject_type, :subject_id ]
  end
end
