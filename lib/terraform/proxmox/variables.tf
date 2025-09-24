# Proxmox provider configuration
variable "api_url" {
  type        = string
  description = "API Url endpoint"
}

variable "username" {
  type        = string
  description = "API username"
}

variable "user" {
  type        = string
  description = "API username (alias for username)"
  default     = ""
}

variable "tls_insecure" {
  type        = bool
  description = "Skip TLS verification"
  default     = true
}

variable "password" {
  type        = string
  description = "API password"
}

# Node configuration
variable "name" {
  type        = string
  description = "Name"
}

variable "hostname" {
  type        = string
  description = "Container hostname"
  default     = ""
}

variable "node_root_password" {
  type        = string
  description = "Root password for the node"
  sensitive   = true
}

# Proxmox-specific variables  
variable "node" {
  type        = string
  description = "Proxmox target node"
}

variable "ostemplate" {
  type        = string
  description = "LXC template to use"
  default     = "local:vztmpl/ubuntu-20.04-standard_20.04-1_amd64.tar.gz"
}

variable "storage" {
  type        = string
  description = "Storage backend"
}

variable "bridge" {
  type        = string
  description = "Network bridge"
  default     = "vmbr0"
}

variable "enable_nesting" {
  type        = bool
  description = "Enable container nesting (requires root@pam permissions)"
  default     = false
}

# Network configuration
variable "ip_address" {
  type        = string
  description = "Static IP address for the container (e.g., 192.168.1.100/24)"
  default     = "dhcp"
}

variable "gateway" {
  type        = string
  description = "Network gateway"
  default     = ""
}

# Resource allocation
variable "cpu_cores" {
  type        = number
  description = "Number of CPU cores"
  default     = 2
}

variable "memory_mb" {
  type        = number
  description = "Memory in MB"
  default     = 2048
}

variable "storage_gb" {
  type        = number
  description = "Storage size in GB"
  default     = 20
}

# Database configuration
variable "database_type" {
  type        = string
  description = "Database type (postgresql, mysql, etc.)"
  default     = "postgresql"
}

variable "database_version" {
  type        = string
  description = "Database version"
  default     = "15"
}

variable "node_id" {
  type        = string
  description = "Node ID from application"
}

variable "is_replica" {
  type        = bool
  description = "Whether this is a replica node"
  default     = false
}

# SSH and provisioning
variable "ssh_public_key" {
  type        = string
  description = "SSH Public Key"
}

variable "ssh_private_key" {
  type        = string
  description = "SSH Private Key for provisioning"
  sensitive   = true
}

variable "cloud_init_script" {
  type        = string
  description = "Path to the cloud-init script file"
  default     = ""
}

# Backward compatibility variables (may be passed but not used in new structure)
variable "template_storage" {
  type        = string
  description = "Template storage (legacy variable for backward compatibility)"
  default     = ""
}

variable "template_template" {
  type        = string
  description = "Template template (legacy variable for backward compatibility)"
  default     = ""
}

variable "disk_size" {
  type        = string
  description = "Disk size (legacy variable, use storage_gb instead)"
  default     = ""
}

variable "primary_node_ip" {
  type        = string
  description = "Primary node IP for replica configuration"
  default     = ""
}
