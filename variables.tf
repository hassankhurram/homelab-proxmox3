# ---- Proxmox connection -----------------------------------------------------

variable "pve_endpoint" {
  description = "Proxmox API endpoint, e.g. https://192.168.1.101:8006/"
  type        = string
}

variable "pve_api_token" {
  description = "API token id+secret: 'terraform@pve!tf=<uuid>'"
  type        = string
  sensitive   = true
}

variable "pve_insecure" {
  description = "Skip TLS verify (self-signed PVE cert)"
  type        = bool
  default     = true
}

variable "pve_node" {
  description = "Proxmox node name (hostname of the box)"
  type        = string
}

variable "pve_ssh_user" {
  description = "SSH user for node-level ops"
  type        = string
  default     = "root"
}

variable "pve_ssh_private_key" {
  description = "Path to the private key matching the installed pubkey"
  type        = string
  default     = "~/.ssh/proxmox_homelab"
}

# ---- Storage ----------------------------------------------------------------

variable "storage_pool" {
  description = "Datastore for VM/CT disks"
  type        = string
  default     = "local-lvm"
}

variable "snippet_storage" {
  description = "Datastore that allows 'snippets' (for cloud-init user-data)"
  type        = string
  default     = "local"
}

variable "image_storage" {
  description = "Datastore for downloaded cloud images / templates"
  type        = string
  default     = "local"
}

# ---- Network ----------------------------------------------------------------

variable "internal_bridge" {
  description = "Internal isolated bridge name"
  type        = string
  default     = "vmbr1"
}

variable "internal_cidr" {
  description = "Internal subnet CIDR"
  type        = string
  default     = "10.10.10.0/24"
}

variable "internal_gateway" {
  description = "Gateway IP (the netservices LXC) on the internal subnet"
  type        = string
  default     = "10.10.10.1"
}

variable "lan_bridge" {
  description = "Existing LAN bridge with uplink (for the router LXC's WAN side)"
  type        = string
  default     = "vmbr0"
}

# ---- Access -----------------------------------------------------------------

variable "ssh_public_keys" {
  description = "Public keys injected into every guest via cloud-init"
  type        = list(string)
}

variable "tailscale_authkey" {
  description = "Reusable, pre-approved Tailscale auth key for the subnet router"
  type        = string
  sensitive   = true
}

# ---- VMs --------------------------------------------------------------------

variable "vms" {
  description = "Map of VMs to create on the internal subnet"
  type = map(object({
    vmid            = number
    ip              = string # /24 host address on internal_cidr
    cores           = number
    memory          = number # MB
    disk_gb         = number
    install_coolify = optional(bool, false)
  }))
  default = {
    staging   = { vmid = 9010, ip = "10.10.10.10", cores = 4, memory = 8192, disk_gb = 120 }
    prod      = { vmid = 9020, ip = "10.10.10.20", cores = 6, memory = 16384, disk_gb = 120, install_coolify = true }
    backup    = { vmid = 9030, ip = "10.10.10.30", cores = 2, memory = 8192, disk_gb = 120 }
    workplace = { vmid = 9040, ip = "10.10.10.40", cores = 6, memory = 16384, disk_gb = 256 }
  }
}
