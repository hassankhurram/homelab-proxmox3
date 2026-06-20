# Internal isolated bridge — no physical NIC attached. The home router never
# sees this subnet; the netservices LXC is its gateway/NAT/DNS.
resource "proxmox_network_linux_bridge" "internal" {
  node_name = var.pve_node
  name      = var.internal_bridge
  comment   = "internal homelab subnet (terraform-managed)"
  # No 'ports' => not bridged to any physical interface.
  autostart = true
}
