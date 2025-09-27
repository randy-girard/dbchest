class CreateMonitoringConfigs < ActiveRecord::Migration[8.0]
  def change
    create_table :monitoring_configs do |t|
      t.references :node, null: false, foreign_key: true
      t.string :config_type, null: false
      t.jsonb :thresholds, default: {}
      t.boolean :enabled, default: true

      t.timestamps
    end

    add_index :monitoring_configs, [ :node_id, :config_type ], unique: true
    add_index :monitoring_configs, :config_type
    add_index :monitoring_configs, :enabled
    add_index :monitoring_configs, :thresholds, using: :gin
  end
end
