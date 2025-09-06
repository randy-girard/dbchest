class CreateProviderTypeOptions < ActiveRecord::Migration[8.0]
  def change
    create_table :provider_type_options do |t|
      t.references :provider_type, null: false, foreign_key: true
      t.string :key
      t.string :label
      t.boolean :required
      t.boolean :sensitive

      t.timestamps
    end

    provider = ProviderType.find_by(key: "proxmox")
    provider.provider_type_options.create(
      key: "api_url",
      label: "API URL",
      required: true,
      sensitive: true
    )
    provider.provider_type_options.create(
      key: "username",
      label: "Username",
      required: true,
      sensitive: true
    )
    provider.provider_type_options.create(
      key: "password",
      label: "Password",
      required: true,
      sensitive: true
    )
  end
end
