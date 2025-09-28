# DigitalOcean Provider Variables
variable "api_token" {
  description = "DigitalOcean API token"
  type        = string
  sensitive   = true
}

# Droplet Configuration
variable "name" {
  description = "Name of the droplet"
  type        = string
}

variable "region" {
  description = "DigitalOcean region"
  type        = string
  default     = "nyc1"
}

variable "size" {
  description = "Droplet size"
  type        = string
  default     = "s-1vcpu-1gb"
}

variable "image" {
  description = "Droplet image"
  type        = string
  default     = "ubuntu-22-04-x64"
}

# SSH Configuration
variable "ssh_key_id" {
  description = "SSH key ID or name"
  type        = string
  default     = ""
}

# Network Configuration
variable "vpc_uuid" {
  description = "VPC UUID"
  type        = string
  default     = ""
}

# Database Configuration
variable "database_type" {
  description = "Type of database (postgresql, mysql, mongodb, etc.)"
  type        = string
  default     = "postgresql"
}

variable "database_port" {
  description = "Database port"
  type        = string
  default     = "5432"
}

# Cloud-init Configuration
variable "user_data" {
  description = "Cloud-init user data script"
  type        = string
  default     = ""
}

# Storage Configuration
variable "create_volume" {
  description = "Whether to create an additional volume for database storage"
  type        = bool
  default     = false
}

variable "volume_size" {
  description = "Size of the additional volume in GB"
  type        = number
  default     = 100
}

variable "volume_filesystem" {
  description = "Filesystem type for the volume"
  type        = string
  default     = "ext4"
}

# Backup Configuration
variable "enable_backups" {
  description = "Enable automatic backups"
  type        = bool
  default     = true
}

variable "resize_disk" {
  description = "Allow disk resizing"
  type        = bool
  default     = true
}

# Firewall Configuration
variable "create_firewall" {
  description = "Whether to create a firewall"
  type        = bool
  default     = true
}

variable "ssh_source_addresses" {
  description = "Source addresses allowed for SSH access"
  type        = list(string)
  default     = ["0.0.0.0/0", "::/0"]
}

variable "database_source_addresses" {
  description = "Source addresses allowed for database access"
  type        = list(string)
  default     = ["0.0.0.0/0", "::/0"]
}

variable "monitoring_source_addresses" {
  description = "Source addresses allowed for monitoring access"
  type        = list(string)
  default     = ["0.0.0.0/0", "::/0"]
}

# Reserved IP Configuration
variable "create_reserved_ip" {
  description = "Whether to create a reserved IP"
  type        = bool
  default     = false
}

# Project Configuration
variable "create_project" {
  description = "Whether to create a project"
  type        = bool
  default     = false
}

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = ""
}

variable "environment" {
  description = "Environment (development, staging, production)"
  type        = string
  default     = "production"
}

# Node-specific variables (for compatibility with existing system)
variable "hostname" {
  description = "Hostname for the droplet"
  type        = string
  default     = ""
}

variable "node_root_password" {
  description = "Root password for the node"
  type        = string
  sensitive   = true
  default     = ""
}

# Resource limits
variable "cpu_cores" {
  description = "Number of CPU cores (informational, size determines actual allocation)"
  type        = number
  default     = 1
}

variable "memory_mb" {
  description = "Memory in MB (informational, size determines actual allocation)"
  type        = number
  default     = 1024
}

variable "storage_gb" {
  description = "Storage in GB (informational, size determines actual allocation)"
  type        = number
  default     = 25
}

# Compatibility variables for existing DBChest integration
variable "ip_address" {
  description = "IP address assignment method (dhcp or static IP)"
  type        = string
  default     = "dhcp"
}

variable "gateway" {
  description = "Gateway IP address (for static IP configuration)"
  type        = string
  default     = ""
}

variable "bridge" {
  description = "Network bridge (not applicable to DigitalOcean, kept for compatibility)"
  type        = string
  default     = ""
}

variable "enable_nesting" {
  description = "Enable container nesting (not applicable to DigitalOcean, kept for compatibility)"
  type        = bool
  default     = false
}
