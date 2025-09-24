terraform {
  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "3.0.2-rc03"
    }
  }
}

# Configure the Proxmox Provider
provider "proxmox" {
  pm_api_url      = var.api_url
  pm_user         = var.user != "" ? var.user : var.username
  pm_password     = var.password
  pm_tls_insecure = var.tls_insecure
}

# Main LXC Container Resource
resource "proxmox_lxc" "container" {
  target_node  = var.node
  hostname     = var.hostname != "" ? var.hostname : var.name
  ostemplate   = var.ostemplate
  password     = var.node_root_password
  unprivileged = true
  onboot       = true
  start        = true

  # Resource allocation - use variables instead of hardcoded values
  cores  = var.cpu_cores
  memory = var.memory_mb
  swap   = var.memory_mb / 2

  rootfs {
    storage = var.storage
    size    = "${var.storage_gb}G"
  }

  network {
    name   = "eth0"
    bridge = var.bridge
    ip     = var.ip_address != "dhcp" ? var.ip_address : "dhcp"
    gw     = var.gateway != "" && var.ip_address != "dhcp" ? var.gateway : null
  }

  # Database-specific features (only if user has root@pam permissions)
  dynamic "features" {
    for_each = var.enable_nesting ? [1] : []
    content {
      nesting = var.database_type == "postgresql" ? true : false
    }
  }

  ssh_public_keys = var.ssh_public_key

  # Tags for organization
  tags = join(",", [var.database_type, var.database_version, var.is_replica ? "replica" : "primary"])

  # Wait for container to be SSH-ready
  provisioner "remote-exec" {
    inline = [
      "while ! systemctl is-active --quiet ssh; do echo 'Waiting for SSH service...'; sleep 5; done",
      "echo 'Container is ready for DBChest provisioning'"
    ]

    connection {
      type        = "ssh"
      user        = "root"
      private_key = var.ssh_private_key
      host        = split("/", self.network[0].ip)[0]
      timeout     = "5m"
    }
  }

  # Copy the setup script
  provisioner "file" {
    source      = var.cloud_init_script
    destination = "/tmp/dbchest_setup.sh"

    connection {
      type        = "ssh"
      user        = "root"
      private_key = var.ssh_private_key
      host        = split("/", self.network[0].ip)[0]
      timeout     = "2m"
    }
  }

  # Execute the setup script in detached mode
  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/dbchest_setup.sh",
      "echo 'Starting DBChest setup in detached mode...'",
      "mkdir -p /var/log",
      # Create a wrapper script that properly detaches
      "cat > /tmp/dbchest_wrapper.sh << 'EOF'",
      "#!/bin/bash",
      "# Detach from SSH session completely",
      "nohup setsid /tmp/dbchest_setup.sh > /var/log/dbchest-setup.log 2>&1 < /dev/null &",
      "# Write the PID for monitoring",
      "echo $! > /var/log/dbchest-setup.pid",
      "exit 0",
      "EOF",
      "chmod +x /tmp/dbchest_wrapper.sh",
      "echo 'Launching detached setup process...'",
      "/tmp/dbchest_wrapper.sh",
      "sleep 2",
      "echo 'DBChest setup started in background'",
      "echo 'Monitor progress with: tail -f /var/log/dbchest-setup.log'",
      "echo 'Check if running with: ps aux | grep dbchest_setup.sh'"
    ]

    connection {
      type        = "ssh"
      user        = "root"
      private_key = var.ssh_private_key
      host        = split("/", self.network[0].ip)[0]
      timeout     = "10m" # Longer timeout for database setup
    }
  }
}

# Outputs
output "vmid" {
  description = "Container ID"
  value       = proxmox_lxc.container.vmid
}

output "node" {
  description = "Target node where container was created"
  value       = var.node
}

output "hostname" {
  description = "Container hostname"
  value       = proxmox_lxc.container.hostname
}

output "ip_address" {
  description = "Container IP address"
  value       = split("/", var.ip_address)[0]
}

output "network_interfaces" {
  description = "Network interface configuration"
  value       = proxmox_lxc.container.network
}
