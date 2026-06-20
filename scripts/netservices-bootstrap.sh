#!/usr/bin/env bash
# Configures the netservices LXC as: NAT router + DNS/DHCP + Tailscale subnet router.
# Applied after `terraform apply` via:
#   pct push 9001 scripts/netservices-bootstrap.sh /root/bootstrap.sh
#   pct exec 9001 -- bash /root/bootstrap.sh "<TAILSCALE_AUTHKEY>"
set -euo pipefail

AUTHKEY="${1:?usage: bootstrap.sh <tailscale-authkey>}"
INTERNAL_CIDR="10.10.10.0/24"
WAN_IF="eth0"
LAN_IF="eth1"

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y dnsmasq nftables curl

# ---- IP forwarding ----------------------------------------------------------
cat >/etc/sysctl.d/99-router.conf <<EOF
net.ipv4.ip_forward=1
EOF
# Only our file — `sysctl --system` errors on host-protected keys in an
# unprivileged CT and would abort under `set -e`.
sysctl -p /etc/sysctl.d/99-router.conf

# ---- NAT (nftables) ---------------------------------------------------------
cat >/etc/nftables.conf <<EOF
#!/usr/sbin/nft -f
flush ruleset
table inet filter {
  chain forward {
    type filter hook forward priority 0; policy accept;
  }
}
table ip nat {
  chain postrouting {
    type nat hook postrouting priority 100; policy accept;
    ip saddr ${INTERNAL_CIDR} oifname "${WAN_IF}" masquerade
  }
}
EOF
systemctl enable --now nftables
nft -f /etc/nftables.conf

# ---- dnsmasq: DNS + DHCP pool for ephemeral guests --------------------------
# Static VMs get their IP from cloud-init; the pool covers preview/ad-hoc VMs.
cat >/etc/dnsmasq.d/homelab.conf <<EOF
interface=${LAN_IF}
bind-interfaces
domain=homelab.internal
# DHCP pool for dynamic guests (.100-.200); static VMs live below .100
dhcp-range=10.10.10.100,10.10.10.200,12h
dhcp-option=option:router,10.10.10.1
dhcp-option=option:dns-server,10.10.10.1
# Upstream resolvers
server=1.1.1.1
server=9.9.9.9
# Local A records for the known VMs
address=/staging.homelab.internal/10.10.10.10
address=/prod.homelab.internal/10.10.10.20
address=/backup.homelab.internal/10.10.10.30
address=/workplace.homelab.internal/10.10.10.40
EOF
systemctl enable --now dnsmasq
systemctl restart dnsmasq

# ---- Tailscale subnet router ------------------------------------------------
curl -fsSL https://tailscale.com/install.sh | sh
tailscale up \
  --authkey "${AUTHKEY}" \
  --advertise-routes="${INTERNAL_CIDR}" \
  --hostname=homelab-netservices \
  --accept-dns=false

echo "netservices ready. Approve the ${INTERNAL_CIDR} route in the Tailscale admin console."
