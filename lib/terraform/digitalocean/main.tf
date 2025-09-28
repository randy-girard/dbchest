terraform {
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
  }
}

# Configure the DigitalOcean Provider
provider "digitalocean" {
  token = var.api_token
}

# Data source for SSH key
data "digitalocean_ssh_key" "default" {
  count = var.ssh_key_id != "" ? 1 : 0
  name  = var.ssh_key_id
}

# Data source for VPC
data "digitalocean_vpc" "selected" {
  count = var.vpc_uuid != "" ? 1 : 0
  id    = var.vpc_uuid
}

# Main Droplet Resource
resource "digitalocean_droplet" "database_node" {
  image     = var.image
  name      = var.name
  region    = var.region
  size      = var.size
  
  # SSH Keys
  ssh_keys = var.ssh_key_id != "" ? [data.digitalocean_ssh_key.default[0].id] : []
  
  # VPC
  vpc_uuid = var.vpc_uuid != "" ? var.vpc_uuid : null
  
  # Enable monitoring
  monitoring = true
  
  # Enable backups if specified
  backups = var.enable_backups
  
  # User data for cloud-init
  user_data = var.user_data
  
  # Tags
  tags = [
    "dbchest",
    "database",
    var.database_type,
    var.environment != "" ? var.environment : "production"
  ]
  
  # Resize disk if needed
  resize_disk = var.resize_disk
  
  # Graceful shutdown
  graceful_shutdown = true
  
  # Lifecycle management
  lifecycle {
    create_before_destroy = false
    prevent_destroy       = false
  }
}

# Firewall rules for database access
resource "digitalocean_firewall" "database_firewall" {
  count = var.create_firewall ? 1 : 0
  name  = "${var.name}-firewall"

  droplet_ids = [digitalocean_droplet.database_node.id]

  # SSH access
  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = var.ssh_source_addresses
  }

  # Database port access
  inbound_rule {
    protocol         = "tcp"
    port_range       = var.database_port
    source_addresses = var.database_source_addresses
  }

  # HTTP/HTTPS for monitoring and management
  inbound_rule {
    protocol         = "tcp"
    port_range       = "80"
    source_addresses = var.monitoring_source_addresses
  }

  inbound_rule {
    protocol         = "tcp"
    port_range       = "443"
    source_addresses = var.monitoring_source_addresses
  }

  # Allow all outbound traffic
  outbound_rule {
    protocol              = "tcp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "udp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "icmp"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
}

# Volume for database storage (optional)
resource "digitalocean_volume" "database_storage" {
  count                   = var.create_volume ? 1 : 0
  region                  = var.region
  name                    = "${var.name}-storage"
  size                    = var.volume_size
  initial_filesystem_type = var.volume_filesystem
  description             = "Database storage volume for ${var.name}"
  
  tags = [
    "dbchest",
    "database-storage",
    var.database_type
  ]
}

# Attach volume to droplet
resource "digitalocean_volume_attachment" "database_storage_attachment" {
  count      = var.create_volume ? 1 : 0
  droplet_id = digitalocean_droplet.database_node.id
  volume_id  = digitalocean_volume.database_storage[0].id
}

# Reserved IP (optional)
resource "digitalocean_reserved_ip" "database_ip" {
  count  = var.create_reserved_ip ? 1 : 0
  region = var.region
  type   = "assign"
  droplet = digitalocean_droplet.database_node.id
}

# Database-specific project (optional)
resource "digitalocean_project" "database_project" {
  count       = var.create_project ? 1 : 0
  name        = var.project_name != "" ? var.project_name : "${var.name}-project"
  description = "Database project for ${var.name}"
  purpose     = "Database"
  environment = var.environment != "" ? var.environment : "Production"
  
  resources = [
    digitalocean_droplet.database_node.urn
  ]
}

# Outputs
output "droplet_id" {
  description = "ID of the created droplet"
  value       = digitalocean_droplet.database_node.id
}

output "droplet_name" {
  description = "Name of the created droplet"
  value       = digitalocean_droplet.database_node.name
}

output "ipv4_address" {
  description = "Public IPv4 address of the droplet"
  value       = digitalocean_droplet.database_node.ipv4_address
}

output "ipv4_address_private" {
  description = "Private IPv4 address of the droplet"
  value       = digitalocean_droplet.database_node.ipv4_address_private
}

output "ipv6_address" {
  description = "Public IPv6 address of the droplet"
  value       = digitalocean_droplet.database_node.ipv6_address
}

output "reserved_ip" {
  description = "Reserved IP address (if created)"
  value       = var.create_reserved_ip ? digitalocean_reserved_ip.database_ip[0].ip_address : null
}

output "volume_id" {
  description = "ID of the created volume (if created)"
  value       = var.create_volume ? digitalocean_volume.database_storage[0].id : null
}

output "firewall_id" {
  description = "ID of the created firewall (if created)"
  value       = var.create_firewall ? digitalocean_firewall.database_firewall[0].id : null
}

output "region" {
  description = "Region where the droplet was created"
  value       = digitalocean_droplet.database_node.region
}

output "size" {
  description = "Size of the created droplet"
  value       = digitalocean_droplet.database_node.size
}

output "status" {
  description = "Status of the droplet"
  value       = digitalocean_droplet.database_node.status
}
