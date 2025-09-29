ProviderType.find_or_create_by(
  name: "Proxmox",
  key: "proxmox"
)

provider = ProviderType.find_by(key: "proxmox")
provider.provider_type_options.find_or_create_by(
  key: "api_url",
  label: "API URL",
  required: true,
  sensitive: true
)
provider.provider_type_options.find_or_create_by(
  key: "username",
  label: "Username",
  required: true,
  sensitive: true
)
provider.provider_type_options.find_or_create_by(
  key: "password",
  label: "Password",
  required: true,
  sensitive: true
)

provider.provider_type_node_options.find_or_create_by(
  key: "template_storage",
  label: "Storage",
  required: true
)
provider.provider_type_node_options.find_or_create_by(
  key: "template_template",
  label: "Template",
  required: true
)

provider.provider_type_node_options.find_or_create_by(
  key: "disk_size",
  label: "Disk Size",
  required: true
)
provider.provider_type_node_options.find_or_create_by(
  key: "node",
  label: "Node",
  required: true
)
provider.provider_type_node_options.find_or_create_by(
  key: "storage",
  label: "Storage",
  required: true
)
provider.provider_type_node_options.find_or_create_by(
  key: "ip_address",
  label: "IP Address",
  required: true
)
provider.provider_type_node_options.find_or_create_by(
  key: "gateway",
  label: "Gateway",
  required: true
)

# Create DigitalOcean Provider Type
digitalocean_provider = ProviderType.find_or_create_by(
  name: "DigitalOcean",
  key: "digitalocean"
)

digitalocean_provider.provider_type_options.find_or_create_by(
  key: "api_token",
  label: "API Token",
  required: true,
  sensitive: true
)

digitalocean_provider.provider_type_node_options.find_or_create_by(
  key: "region",
  label: "Region",
  required: true
)
digitalocean_provider.provider_type_node_options.find_or_create_by(
  key: "size",
  label: "Droplet Size",
  required: true
)
digitalocean_provider.provider_type_node_options.find_or_create_by(
  key: "image",
  label: "Image",
  required: true
)
digitalocean_provider.provider_type_node_options.find_or_create_by(
  key: "ssh_key_id",
  label: "SSH Key",
  required: false
)
digitalocean_provider.provider_type_node_options.find_or_create_by(
  key: "vpc_uuid",
  label: "VPC UUID",
  required: false
)

# Database types and versions are now created via migration
# See db/migrate/*_populate_database_types_and_versions.rb
