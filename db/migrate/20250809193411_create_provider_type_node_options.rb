class CreateProviderTypeNodeOptions < ActiveRecord::Migration[8.0]
  def change
    create_table :provider_type_node_options do |t|
      t.references :provider_type, null: false, foreign_key: true
      t.string :key
      t.string :label
      t.boolean :required, default: false

      t.timestamps
    end

    provider = ProviderType.find_by(key: "proxmox")
    provider.provider_type_node_options.create(
      key: "template_storage",
      label: "Storage",
      required: true
    )
    provider.provider_type_node_options.create(
      key: "template_template",
      label: "Template",
      required: true
    )

    provider.provider_type_node_options.create(
      key: "disk_size",
      label: "Disk Size",
      required: true
    )
    provider.provider_type_node_options.create(
      key: "node",
      label: "Node",
      required: true
    )
    provider.provider_type_node_options.create(
      key: "storage",
      label: "Storage",
      required: true
    )
    provider.provider_type_node_options.create(
      key: "ip_address",
      label: "IP Address",
      required: true
    )
    provider.provider_type_node_options.create(
      key: "gateway",
      label: "Gateway",
      required: true
    )
  end
end
