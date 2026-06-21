#!/usr/bin/env bash
set -e
mkdir -p /etc/homelab
cat > /etc/homelab/secrets.env <<EOF
DOMAIN=${DOMAIN}
CF_TOKEN=${CF_TOKEN}
CF_ZONE_ID=${CF_ZONE}
CF_ACCOUNT_ID=${CF_ACCOUNT}
NPM_ALT_URL=http://100.100.70.20:81
NPM_EMAIL=${NPM_EMAIL}
NPM_PASS=${NPM_PASS}
NPM_CERT_ID=1
COOLIFY_URL=http://10.10.10.20:8000
COOLIFY_TOKEN=
EOF
chmod 600 /etc/homelab/secrets.env

cat > /usr/local/bin/homelab-deploy <<'WRAP'
#!/usr/bin/env bash
# Homelab deploy wrapper (token model A) — secrets root-only in /etc/homelab/secrets.env.
# Run via: sudo homelab-deploy <cmd> ...
set -euo pipefail
. /etc/homelab/secrets.env
cmd="${1:-help}"; shift || true
cf(){ curl -s -H "Authorization: Bearer $CF_TOKEN" -H "Content-Type: application/json" "$@"; }
npm_tok(){ curl -s "$NPM_ALT_URL/api/tokens" -H 'Content-Type: application/json' \
  -d "{\"identity\":\"$NPM_EMAIL\",\"secret\":\"$NPM_PASS\"}" \
  | python3 -c 'import sys,json;print(json.load(sys.stdin)["token"])'; }
case "$cmd" in
  dns-list)
    cf "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records?per_page=100" \
    | python3 -c 'import sys,json;[print(r["type"],r["name"],"->",r["content"]) for r in json.load(sys.stdin)["result"]]' ;;
  dns-add) # dns-add <name> <type> <content> [proxied]
    cf -X POST "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records" \
      -d "{\"type\":\"$2\",\"name\":\"$1\",\"content\":\"$3\",\"ttl\":1,\"proxied\":${4:-false}}" \
    | python3 -c 'import sys,json;d=json.load(sys.stdin);print("ok" if d["success"] else d["errors"])' ;;
  private-host) # private-host <sub> <fwd_ip> <fwd_port>  -> <sub>.lab.DOMAIN (tailnet-only)
    tok=$(npm_tok)
    curl -s "$NPM_ALT_URL/api/nginx/proxy-hosts" -H "Authorization: Bearer $tok" -H 'Content-Type: application/json' \
      -d "{\"domain_names\":[\"$1.lab.$DOMAIN\"],\"forward_scheme\":\"http\",\"forward_host\":\"$2\",\"forward_port\":$3,\"certificate_id\":$NPM_CERT_ID,\"ssl_forced\":true,\"http2_support\":true,\"block_exploits\":true,\"allow_websocket_upgrade\":true,\"access_list_id\":0,\"advanced_config\":\"\",\"locations\":[],\"meta\":{\"letsencrypt_agree\":false,\"dns_challenge\":false}}" \
    | python3 -c 'import sys,json;d=json.load(sys.stdin);print("created",d["id"]) if d.get("id") else print(d)' ;;
  coolify) # coolify <GET|POST|...> <api-path> [json-body]
    [ -n "${COOLIFY_TOKEN:-}" ] || { echo "Set COOLIFY_TOKEN in /etc/homelab/secrets.env (create Coolify admin + API token first)"; exit 1; }
    curl -s -X "$1" "$COOLIFY_URL/api/v1$2" -H "Authorization: Bearer $COOLIFY_TOKEN" -H 'Content-Type: application/json' ${3:+-d "$3"} ;;
  *) echo "usage: sudo homelab-deploy <dns-list | dns-add <name> <type> <content> [proxied] | private-host <sub> <ip> <port> | coolify <method> <path> [body]>" ;;
esac
WRAP
chmod 755 /usr/local/bin/homelab-deploy

printf 'harris ALL=(root) NOPASSWD: /usr/local/bin/homelab-deploy\nhassan ALL=(root) NOPASSWD: /usr/local/bin/homelab-deploy\n' > /etc/sudoers.d/homelab
chmod 440 /etc/sudoers.d/homelab

cat > /home/shared/homelab/WORKSPACE.md <<'DOC'
# Workspace deploy agent (for Claude/Gemini/Codex)

This box can **develop and deploy** to the orthosuite homelab. Deploy actions go through a
root-owned wrapper (secrets never exposed to users):

    sudo homelab-deploy dns-list
    sudo homelab-deploy dns-add <fqdn> <A|CNAME> <content> [true|false]
    sudo homelab-deploy private-host <sub> <internal_ip> <port>   # -> <sub>.lab.orthosuite.net (tailnet-only, TLS)
    sudo homelab-deploy coolify <GET|POST> <api-path> [json]      # needs COOLIFY_TOKEN set

Topology: internal subnet 10.10.10.0/24 (this VM = .40). Coolify (PaaS) at 10.10.10.20:8000.
Private apps are exposed as *.lab.orthosuite.net via tailscale-alt's NPM (tailnet-only).
Public apps go through jarvis (gated — ask a human). Infra (VMs/LXC) is Terraform in this
repo but applying it needs host root (gated — ask a human). See CLAUDE.md for full context.
DOC
chgrp shared /home/shared/homelab/WORKSPACE.md 2>/dev/null || true
chmod 664 /home/shared/homelab/WORKSPACE.md 2>/dev/null || true
echo AGENT_BUILT
visudo -cf /etc/sudoers.d/homelab
