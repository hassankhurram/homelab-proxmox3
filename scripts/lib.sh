#!/usr/bin/env bash
# Shared config + helpers for homelab scripts. Source this; don't run directly.
# Secrets are read from terraform.tfvars (gitignored) — never hardcoded here.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TFVARS="${TFVARS:-$REPO_DIR/terraform.tfvars}"

# Node is reached via the Tailscale LXC (NPM forwards). Override via env if it moves.
PVE_HOST="${PVE_HOST:-100.100.70.50}"
PVE_API_PORT="${PVE_API_PORT:-8009}"   # NPM -> host:8006
PVE_SSH_PORT="${PVE_SSH_PORT:-2222}"   # NPM -> host:22
PVE_SSH_USER="${PVE_SSH_USER:-root}"
PVE_SSH_KEY="${PVE_SSH_KEY:-$HOME/.ssh/proxmox_homelab}"
PVE_ENDPOINT="https://${PVE_HOST}:${PVE_API_PORT}"
NETSERVICES_VMID="${NETSERVICES_VMID:-9001}"

_tfvar() { # _tfvar <key> -> value (from terraform.tfvars)
  [ -f "$TFVARS" ] || { echo "ERROR: $TFVARS not found" >&2; return 1; }
  grep -E "^[[:space:]]*$1[[:space:]]*=" "$TFVARS" | head -1 | sed -E 's/^[^=]+=[[:space:]]*"([^"]+)".*/\1/'
}

pve_token()   { _tfvar pve_api_token; }
ts_authkey()  { _tfvar tailscale_authkey; }

pve_api() { # pve_api METHOD /path [curl-args...]
  local method="$1" path="$2"; shift 2
  curl -sk --max-time 30 -X "$method" "${PVE_ENDPOINT}/api2/json${path}" \
    -H "Authorization: PVEAPIToken=$(pve_token)" "$@"
}

pve_ssh() { # pve_ssh "command on the host"
  ssh -i "$PVE_SSH_KEY" -p "$PVE_SSH_PORT" \
    -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 -o BatchMode=yes \
    "${PVE_SSH_USER}@${PVE_HOST}" "$@"
}

pve_scp() { # pve_scp <local> <remote-path-on-host>
  scp -i "$PVE_SSH_KEY" -P "$PVE_SSH_PORT" \
    -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 \
    "$1" "${PVE_SSH_USER}@${PVE_HOST}:$2"
}

say()  { printf '\033[1;36m▶ %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m✔ %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }
