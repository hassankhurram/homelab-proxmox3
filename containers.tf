# Debian LXC template (downloaded declaratively to the node).
resource "proxmox_download_file" "debian_lxc" {
  content_type = "vztmpl"
  datastore_id = var.image_storage
  node_name    = var.pve_node
  url          = "http://download.proxmox.com/images/system/debian-12-standard_12.7-1_amd64.tar.zst"
}

# netservices: router + NAT + DNS/DHCP + Tailscale subnet router.
# Two NICs: WAN on the LAN bridge, LAN as the internal gateway (10.10.10.1).
resource "proxmox_virtual_environment_container" "netservices" {
  node_name = var.pve_node
  vm_id     = 9001

  description = "router / NAT / dnsmasq / tailscale subnet router (terraform-managed)"
  tags        = ["homelab", "infra"]

  # Auto-start on boot, before the VMs (low order = earlier).
  started       = true
  start_on_boot = true
  startup {
    order    = 1
    up_delay = 5
  }

  # Needed for Tailscale (TUN) and nft/NAT inside the container.
  unprivileged = false
  features {
    nesting = true
  }

  operating_system {
    template_file_id = proxmox_download_file.debian_lxc.id
    type             = "debian"
  }

  cpu { cores = 2 }
  memory {
    dedicated = 1024
    swap      = 512
  }

  disk {
    datastore_id = var.storage_pool
    size         = 8
  }

  # WAN side — pulls an IP from your LAN (mgmt/uplink for NAT + tailscale).
  network_interface {
    name   = "eth0"
    bridge = var.lan_bridge
  }

  # LAN side — the internal gateway.
  network_interface {
    name   = "eth1"
    bridge = var.internal_bridge
  }

  initialization {
    hostname = "netservices"

    ip_config {
      ipv4 { address = "dhcp" } # eth0 / WAN
    }
    ip_config {
      ipv4 { address = "${var.internal_gateway}/24" } # eth1 / internal gateway
    }

    user_account {
      keys = var.ssh_public_keys
    }
  }

  # In-guest config (dnsmasq, nftables NAT, tailscale) is applied from
  # scripts/netservices-bootstrap.sh via `pct push` + `pct exec` after create.
  # Kept out of Terraform on purpose: TF owns the container, the script owns
  # what runs inside it. See docs/bootstrap.md.
}
