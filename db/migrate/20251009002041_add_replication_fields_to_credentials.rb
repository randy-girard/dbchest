class AddReplicationFieldsToCredentials < ActiveRecord::Migration[8.0]
  def change
    add_column :credentials, :source_credential_id, :integer
    add_column :credentials, :is_replicated, :boolean, default: false, null: false
    add_index :credentials, :source_credential_id
    add_foreign_key :credentials, :credentials, column: :source_credential_id, on_delete: :cascade
  end
end
