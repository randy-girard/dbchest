class CreateNodeMetrics < ActiveRecord::Migration[8.0]
  def change
    create_table :node_metrics do |t|
      t.references :node, null: false, foreign_key: true
      t.datetime :collected_at, null: false
      t.decimal :cpu_usage_percent, precision: 5, scale: 2
      t.bigint :memory_total_mb
      t.bigint :memory_used_mb
      t.bigint :memory_available_mb
      t.bigint :swap_total_mb
      t.bigint :swap_used_mb
      t.jsonb :disk_usage, default: {}
      t.jsonb :network_stats, default: {}
      t.jsonb :load_average, default: {}
      t.bigint :uptime_seconds

      t.timestamps
    end

    # Indexes for efficient querying
    add_index :node_metrics, [ :node_id, :collected_at ]
    add_index :node_metrics, :collected_at
    add_index :node_metrics, [ :node_id, :created_at ]

    # GIN indexes for JSONB columns
    add_index :node_metrics, :disk_usage, using: :gin
    add_index :node_metrics, :network_stats, using: :gin
    add_index :node_metrics, :load_average, using: :gin
  end
end
