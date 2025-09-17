class AddParentNodeToNodes < ActiveRecord::Migration[8.0]
  def change
    add_reference :nodes, :parent_node, null: true, foreign_key: { to_table: :nodes }
  end
end
