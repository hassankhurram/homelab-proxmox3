# homelab — declarative single-node Proxmox cloud

Infrastructure-as-code for a single Proxmox VE node (Apple Mac Pro 2013, 12c/24t,
64 GB RAM, 1 TB SSD) at a remote location, reached over Tailscale and fronted by
Cloudflare. **Terraform is the source of truth for the Proxmox layer.**

Not HA (single node) — VMs auto-start on boot instead. No GPU passthrough (the
FirePro D500s are useless for ML; Whisper/OCR run on CPU, LLMs go to RunPod/Cloud Run).

## Layers (who owns what)

| Layer | Tool | Scope |
|-------|------|-------|
| Infra (VMs, LXC, bridge, firewall, autostart) | **Terraform** (`bpg/proxmox`) | day-0 / day-1 |
| In-guest base config (zsh, docker, tailscale, dnsmasq) | **cloud-init / bootstrap scripts** (in this repo) | day-1 |
| App deploys (revisions, env, DBs, metrics) | **Coolify** | day-2 |
| Orchestration loop | **Proxmox MCP + `/homelab` skill** | ongoing |

Terraform does **not** manage in-guest app churn — that's Coolify's job. Keep the
boundary clean or the two will fight.

## Topology

```
                 Internet
                    │
              Cloudflare (DNS, later: Tunnel)
                    │
         Public VM (Caddy, on tailnet)            ← public ingress (prod)
                    │  Tailscale
        ┌───────────┴────────────────────────────┐
        │      Proxmox node 192.168.1.101         │
        │                                         │
        │  vmbr0 (LAN 192.168.1.0/24, mgmt only)  │
        │                                         │
        │  netservices LXC  ── gateway 10.10.10.1 │  ← router / NAT / DNS+DHCP
        │   • dnsmasq (DNS + DHCP pool)           │     + Tailscale subnet router
        │   • nftables NAT                        │       advertises 10.10.10.0/24
        │   • tailscale --advertise-routes        │
        │                                         │
        │  vmbr1 (internal 10.10.10.0/24)         │
        │   • staging  VM   10.10.10.10           │
        │   • prod     VM   10.10.10.20  (Coolify)│
        │   • backup   VM   10.10.10.30  (DB+media)│
        └─────────────────────────────────────────┘
```

The home router never assigns VM IPs and never sees the internal subnet.

## Bootstrap order

1. **On the host:** create a Terraform API token (see `docs/bootstrap.md`), install the
   SSH pubkey in `/root/.ssh/authorized_keys`.
2. `terraform init && terraform plan` — review.
3. `terraform apply` creates: `vmbr1`, the `netservices` LXC (router/DNS/Tailscale),
   then the three VMs with cloud-init.
4. Approve the Tailscale subnet route in the admin console.
5. Coolify finishes installing on prod; add staging + backup as remote servers.
6. Point Cloudflare DNS at the public VM; Caddy proxies over Tailscale.

## What I still need from you

- Proxmox **API token** (`terraform@pve!tf`) — commands in `docs/bootstrap.md`.
- Confirm the **SSH pubkey** is in `/root/.ssh/authorized_keys` on the host.
- A **Tailscale auth key** (reusable, pre-approved) for the subnet router.
- Your **Cloudflare domain** + which hostnames map to prod vs staging.
- Confirm the **storage pool name** (default assumed `local-lvm`).
