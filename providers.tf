terraform {
  required_version = ">= 1.6"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.66"
    }
  }
}

provider "proxmox" {
  endpoint  = var.pve_endpoint
  api_token = var.pve_api_token
  insecure  = var.pve_insecure

  # bpg needs SSH for some node-level operations (file uploads, snippets).
  ssh {
    agent    = false
    username = var.pve_ssh_user
    # Reached via the Tailscale LXC + NPM chain; see docs/bootstrap.md.
    private_key = file(var.pve_ssh_private_key)
  }
}
