class AddCascadeDeleteToNodeMetrics < ActiveRecord::Migration[8.0]
  def up
    # Remove the existing foreign key
    remove_foreign_key :node_metrics, :nodes

    # Add it back with cascade delete
    add_foreign_key :node_metrics, :nodes, on_delete: :cascade
  end

  def down
    # Remove the cascade foreign key
    remove_foreign_key :node_metrics, :nodes

    # Add it back without cascade (original behavior)
    add_foreign_key :node_metrics, :nodes
  end
end
