variable "api_url" {
 type = string
 description = "API Url endpoint"
}

variable "username" {
 type = string
 description = "API username"
}

variable "password" {
 type = string
 description = "API password"
}

variable "ssh_public_key" {
 type = string
 description = "SSH Public Key"
}

variable "ip_address" {
 type = string
 description = "IP Address"
}

variable "name" {
  type = string
  description = "Name"
}

variable "disk_size" {
  type = string
  description = "Disk size"
}

variable "storage" {
  type = string
  description = "Storage"
}

variable "template_storage" {
  type = string
  description = "Template Storage"
}

variable "template_template" {
  type = string
  description = "Template template"
}

variable "node" {
  type = string
  description = "Node"
}

variable "gateway" {
 type = string
 description = "Gateway"
}
