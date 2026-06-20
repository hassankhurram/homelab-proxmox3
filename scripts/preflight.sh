#!/usr/bin/env bash
# Read-only health check: connectivity, API, SSH, snippets. Safe to run anytime.
. "$(dirname "$0")/lib.sh"

say "Tailscale reachability to $PVE_HOST"
tailscale ping -c 1 "$PVE_HOST" >/dev/null 2>&1 && ok "tailscale ping" || echo "  (tailscale ping failed — not fatal)"

say "TCP ports"
for p in "$PVE_SSH_PORT" "$PVE_API_PORT"; do
  timeout 6 bash -c "cat </dev/null >/dev/tcp/$PVE_HOST/$p" 2>/dev/null \
    && ok "port $p open" || die "port $p filtered — open it (Tailscale ACL / NPM stream)"
done

say "Proxmox API + token"
ver="$(pve_api GET /version | python3 -c 'import sys,json;print(json.load(sys.stdin)["data"]["version"])' 2>/dev/null)" \
  && ok "API ok (PVE $ver)" || die "API/token check failed"

say "SSH to host"
pve_ssh "true" 2>/dev/null && ok "ssh ok ($(pve_ssh hostname 2>/dev/null))" || die "SSH key not accepted on host"

say "snippets enabled on local"
pve_api GET /storage/local | grep -q snippets && ok "snippets enabled" || echo "  WARN: snippets NOT enabled on 'local' (cloud-init will fail)"

ok "preflight passed"
