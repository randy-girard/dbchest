class AddMetricsApiKeyToNodes < ActiveRecord::Migration[8.0]
  def change
    add_column :nodes, :metrics_api_key, :string
    add_index :nodes, :metrics_api_key, unique: true
  end
end
