#!/usr/bin/env bash
# Reproducible setup for the SECONDARY Tailscale node (LXC 9002, "tailscale-alt").
# Joins a DIFFERENT Tailscale account (account B) and acts as a subnet router for
# the homelab. Run INSIDE the container:
#   pct enter 9002          (from the Proxmox host)   — or —   ssh root@10.10.10.50
#
# The `tailscale up` step is INTERACTIVE: it prints a login URL — open it and sign
# in with ACCOUNT B. Afterwards, approve the advertised route in account B's admin.
#
# Usage: tailscale-alt-setup.sh [routes]   (default routes: 10.10.10.0/24)
set -euo pipefail

ROUTES="${1:-10.10.10.0/24}"
export DEBIAN_FRONTEND=noninteractive

apt-get update -qq
apt-get install -y -qq ethtool curl

# 1. Tailscale
command -v tailscale >/dev/null 2>&1 || curl -fsSL https://tailscale.com/install.sh | sh

# 2. IP forwarding (needed to route for other devices)
echo 'net.ipv4.ip_forward=1' >/etc/sysctl.d/99-ts.conf
sysctl -p /etc/sysctl.d/99-ts.conf

# 3. NIC tuning (UDP GRO forwarding) — persistent
cat >/etc/systemd/system/tailscale-nic-tune.service <<'UNIT'
[Unit]
Description=Tailscale subnet router NIC tuning (UDP GRO forwarding)
After=network-online.target
Wants=network-online.target
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/sbin/ethtool -K eth0 rx-udp-gro-forwarding on rx-gro-list off
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now tailscale-nic-tune.service

# 4. Join the tailnet as a subnet router (INTERACTIVE — sign in with ACCOUNT B)
tailscale up --advertise-routes="${ROUTES}" --accept-dns=false --hostname=tailscale-alt

echo "tailscale-alt up. Now APPROVE the ${ROUTES} route in ACCOUNT B's admin console:"
echo "  Machines -> tailscale-alt -> Edit route settings -> enable ${ROUTES}"
