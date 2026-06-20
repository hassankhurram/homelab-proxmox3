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

  # bpg needs SSH for some node-level operations (snippet/image uploads).
  ssh {
    agent       = false
    username    = var.pve_ssh_user
    private_key = file(pathexpand(var.pve_ssh_private_key))

    # Override the node's SSH target: the real LAN IP (192.168.1.101:22) isn't
    # reachable from here — we go through the Tailscale LXC + NPM chain instead.
    node {
      name    = var.pve_node
      address = var.pve_ssh_address
      port    = var.pve_ssh_port
    }
  }
}
