class AddCascadeDeleteToMonitoringConfigs < ActiveRecord::Migration[8.0]
  def up
    # Remove the existing foreign key
    remove_foreign_key :monitoring_configs, :nodes

    # Add it back with cascade delete
    add_foreign_key :monitoring_configs, :nodes, on_delete: :cascade
  end

  def down
    # Remove the cascade foreign key
    remove_foreign_key :monitoring_configs, :nodes

    # Add it back without cascade (original behavior)
    add_foreign_key :monitoring_configs, :nodes
  end
end
