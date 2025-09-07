ProviderType.create(
  name: "Proxmox",
  key: "proxmox"
)

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