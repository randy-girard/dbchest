terraform {
  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "3.0.2-rc03"
    }
  }
}

provider "proxmox" {
  pm_api_url = var.api_url
  pm_user = var.username
  pm_password = var.password
  pm_tls_insecure = true
}

resource "proxmox_lxc" "container" {
  target_node = var.node

  hostname     = var.name
  ostemplate   = "local:vztmpl/ubuntu-20.04-standard_20.04-1_amd64.tar.gz"
  password     = "supersecret"

  cores        = 1
  memory       = 512
  swap         = 512
  start        = true
  rootfs {
    storage = "storage"
    size    = "8G"
  }

  network {
    name   = "eth0"
    bridge = "vmbr0"
    ip     = var.ip_address
    gw     = var.gateway
  }

  ssh_public_keys = var.ssh_public_key

  # name        = "VM-name"
  #disks {
  #  ide {
  #    ide0 {
  #      cdrom {
  #        iso = "ubuntu-20.04.2-live-server-amd64.iso"
  #      }
  #    }
  #  }
  #  scsi {
  #    scsi0 {
  #      disk {
  #        size = "10"
  #        storage = "vmdisks"
  #      }
  #    }
  #  }
  #}
}

output "vmid" {
  value = proxmox_lxc.container.vmid
}

output "node" {
  value = var.node
}

output "ip_address" {
  value = var.ip_address
}

output "network_interfaces" {
  value = proxmox_lxc.container.network
}
