# Debian LXC template (downloaded declaratively to the node).
resource "proxmox_download_file" "debian_lxc" {
  content_type = "vztmpl"
  datastore_id = var.image_storage
  node_name    = var.pve_node
  url          = "http://download.proxmox.com/images/system/debian-12-standard_12.12-1_amd64.tar.zst"
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

  # Unprivileged (token users can't set feature flags on privileged CTs, and it's
  # safer). Tailscale needs /dev/net/tun, added to the CT config during bootstrap.
  unprivileged = true
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
    bridge = proxmox_network_linux_bridge.internal.name
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

# Secondary Tailscale node on a DIFFERENT Tailscale account. Tailscale is NOT
# auto-installed here — the user SSHes in (root password from tfvars) and installs
# it manually. Internet via netservices NAT; reachable over the subnet route.
resource "proxmox_virtual_environment_container" "tailscale_alt" {
  node_name = var.pve_node
  vm_id     = 9002

  description = "secondary tailscale node (different account, manual install)"
  tags        = ["homelab", "infra", "tailscale-alt"]

  started       = true
  start_on_boot = true
  startup {
    order    = 2
    up_delay = 5
  }

  # Unprivileged + nesting; /dev/net/tun added to the CT config during prep so
  # the user's manual `tailscale up` works.
  unprivileged = true
  features {
    nesting = true
  }

  operating_system {
    template_file_id = proxmox_download_file.debian_lxc.id
    type             = "debian"
  }

  cpu { cores = 1 }
  memory {
    dedicated = 512
    swap      = 512
  }

  disk {
    datastore_id = var.storage_pool
    size         = 8
  }

  network_interface {
    name   = "eth0"
    bridge = proxmox_network_linux_bridge.internal.name
  }

  initialization {
    hostname = "tailscale-alt"

    ip_config {
      ipv4 {
        address = "10.10.10.50/24"
        gateway = var.internal_gateway
      }
    }

    dns {
      servers = [var.internal_gateway]
    }

    user_account {
      keys     = var.ssh_public_keys
      password = var.ts_alt_root_password
    }
  }
}
