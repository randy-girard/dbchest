class CreateNodes < ActiveRecord::Migration[8.0]
  def change
    create_table :nodes do |t|
      t.references :cluster, null: false, foreign_key: true
      t.references :provider, null: false, foreign_key: true
      t.string :name
      t.jsonb :terraform_state, default: {}
      t.string :ssh_private_key
      t.string :ssh_public_key
      t.jsonb :runtime_config, default: {}

      t.timestamps
    end
  end
end
