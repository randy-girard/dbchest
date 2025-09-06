class CreateClusters < ActiveRecord::Migration[8.0]
  def change
    create_table :clusters do |t|
      t.string :name

      t.timestamps
    end
  end
end
