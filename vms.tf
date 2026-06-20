# Debian 12 cloud image (downloaded declaratively).
resource "proxmox_download_file" "debian_cloud" {
  content_type = "iso"
  datastore_id = var.image_storage
  node_name    = var.pve_node
  url          = "https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2"
  file_name    = "debian-12-genericcloud-amd64.img"
}

# Per-VM cloud-init user-data (zsh, docker, + Coolify on prod).
resource "proxmox_virtual_environment_file" "user_data" {
  for_each = var.vms

  content_type = "snippets"
  datastore_id = var.snippet_storage
  node_name    = var.pve_node

  source_raw {
    file_name = "ci-${each.key}.yaml"
    data = templatefile("${path.module}/cloud-init/base.yaml.tftpl", {
      hostname        = each.key
      ssh_keys        = var.ssh_public_keys
      install_coolify = each.value.install_coolify
    })
  }
}

resource "proxmox_virtual_environment_vm" "guest" {
  for_each = var.vms

  node_name   = var.pve_node
  vm_id       = each.value.vmid
  name        = each.key
  description = "homelab ${each.key} (terraform-managed)"
  tags        = ["homelab", each.key]

  # Single node: no HA, just come back on boot.
  on_boot = true
  startup {
    order    = each.value.vmid - 9000 # netservices(1) first, then staging/prod/backup
    up_delay = 10
  }

  agent { enabled = true }

  cpu {
    cores = each.value.cores
    type  = "host"
  }

  memory {
    dedicated = each.value.memory
  }

  disk {
    datastore_id = var.storage_pool
    import_from  = proxmox_download_file.debian_cloud.id
    interface    = "virtio0"
    size         = each.value.disk_gb
  }

  network_device {
    bridge = var.internal_bridge
  }

  initialization {
    datastore_id = var.storage_pool

    ip_config {
      ipv4 {
        address = "${each.value.ip}/24"
        gateway = var.internal_gateway
      }
    }

    dns {
      servers = [var.internal_gateway]
    }

    user_data_file_id = proxmox_virtual_environment_file.user_data[each.key].id
  }

  lifecycle {
    ignore_changes = [
      # Disk image hash churns on upstream refresh; don't recreate live VMs.
      disk[0].import_from,
    ]
  }
}
