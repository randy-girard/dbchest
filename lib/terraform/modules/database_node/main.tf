# Terraform Module: Database Node
# This module provides a reusable abstraction for creating database nodes
# across different providers (Proxmox, DigitalOcean, etc.)

variable "provider_type" {
  description = "Provider type (proxmox, digitalocean)"
  type        = string
}

variable "node_name" {
  description = "Name of the database node"
  type        = string
}

variable "database_type" {
  description = "Type of database (postgresql, mysql, mongodb, cassandra)"
  type        = string
}

variable "database_version" {
  description = "Version of the database"
  type        = string
}

variable "is_replica" {
  description = "Whether this is a replica node"
  type        = bool
  default     = false
}

variable "cpu_cores" {
  description = "Number of CPU cores"
  type        = number
  default     = 2
}

variable "memory_mb" {
  description = "Memory in MB"
  type        = number
  default     = 2048
}

variable "storage_gb" {
  description = "Storage in GB"
  type        = number
  default     = 20
}

variable "cloud_init_script" {
  description = "Path to cloud-init script"
  type        = string
}

variable "ssh_public_key" {
  description = "SSH public key for access"
  type        = string
  default     = ""
}

variable "ssh_private_key" {
  description = "SSH private key for provisioning"
  type        = string
  default     = ""
}

variable "node_root_password" {
  description = "Root password for the node"
  type        = string
  sensitive   = true
}

# Provider-specific variables
variable "provider_config" {
  description = "Provider-specific configuration"
  type        = map(any)
  default     = {}
}

# Outputs
output "node_id" {
  description = "ID of the created node"
  value       = var.provider_type == "proxmox" ? try(module.proxmox_node[0].vmid, null) : null
}

output "node_name" {
  description = "Name of the created node"
  value       = var.node_name
}

output "ip_address" {
  description = "IP address of the node"
  value       = var.provider_type == "proxmox" ? try(module.proxmox_node[0].ip_address, null) : null
}

# Conditional module inclusion based on provider type
module "proxmox_node" {
  count  = var.provider_type == "proxmox" ? 1 : 0
  source = "../proxmox_node"

  hostname            = var.node_name
  database_type       = var.database_type
  database_version    = var.database_version
  is_replica          = var.is_replica
  cpu_cores           = var.cpu_cores
  memory_mb           = var.memory_mb
  storage_gb          = var.storage_gb
  cloud_init_script   = var.cloud_init_script
  ssh_public_key      = var.ssh_public_key
  ssh_private_key     = var.ssh_private_key
  node_root_password  = var.node_root_password

  # Pass provider-specific config
  node                = lookup(var.provider_config, "node", "pve")
  storage             = lookup(var.provider_config, "storage", "local-lvm")
  bridge              = lookup(var.provider_config, "bridge", "vmbr0")
  ostemplate          = lookup(var.provider_config, "ostemplate", "local:vztmpl/ubuntu-22.04-standard_22.04-1_amd64.tar.zst")
  ip_address          = lookup(var.provider_config, "ip_address", "dhcp")
  gateway             = lookup(var.provider_config, "gateway", "")
  enable_nesting      = lookup(var.provider_config, "enable_nesting", true)
}

# Future: Add DigitalOcean module
# module "digitalocean_node" {
#   count  = var.provider_type == "digitalocean" ? 1 : 0
#   source = "../digitalocean_node"
#   ...
# }

