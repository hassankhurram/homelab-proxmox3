# Workspace deploy agent (for Claude / Gemini / Codex)

The workspace VM (9040, `10.10.10.40`; Tailscale `workspace`) is where devs + their AI
assistants develop and deploy to the orthosuite homelab.

## Deploy interface — `sudo homelab-deploy`

Deploy actions run through a **root-owned wrapper** (`/usr/local/bin/homelab-deploy`) that
reads secrets from `/etc/homelab/secrets.env` (root `600`). Users (`harris`, `hassan`)
invoke it via `sudo` (NOPASSWD) — they never see the raw tokens. Built by
`scripts/workspace-agent.sh`.

```
sudo homelab-deploy dns-list
sudo homelab-deploy dns-add <fqdn> <A|CNAME> <content> [true|false]   # Cloudflare
sudo homelab-deploy private-host <sub> <internal_ip> <port>          # -> <sub>.lab.orthosuite.net (tailnet-only, TLS)
sudo homelab-deploy coolify <GET|POST|...> <api-path> [json]         # needs COOLIFY_TOKEN
```

## Scope (current)

- ✅ **App layer**: Cloudflare DNS, private `*.lab` ingress (tailscale-alt NPM), Coolify
  deploys (once `COOLIFY_TOKEN` is set after Coolify admin signup).
- 🔒 **Gated (need a human grant)**:
  - **Infra** (Terraform/Proxmox) — applying needs root SSH to the PVE host (`192.168.1.101`).
  - **Public ingress** (jarvis) — needs the workspace key authorized on jarvis.

## Reach (workspace is natively on the internal subnet)

Coolify `10.10.10.20:8000`, mdnest `10.10.10.60:3236`, PVE API `192.168.1.101:8006`
(via netservices NAT), tailscale-alt NPM `100.100.70.20:81`, Cloudflare (internet).

See `CLAUDE.md` for the full homelab architecture.
