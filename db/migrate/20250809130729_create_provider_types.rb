class CreateProviderTypes < ActiveRecord::Migration[8.0]
  def change
    create_table :provider_types do |t|
      t.string :name
      t.string :key

      t.timestamps
    end
  end
end
