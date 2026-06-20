# CLAUDE.md — homelab (single-node Proxmox cloud)

Declarative IaC for one Proxmox VE node at a remote location, reached over Tailscale,
fronted by Cloudflare. **Terraform (`bpg/proxmox`) is the source of truth for the
Proxmox layer.** Not HA (single node) — VMs auto-start on boot. No GPU passthrough.

## You may write scripts to assist with setup and updates

Helper scripts live in `scripts/` and are the preferred way to drive setup and day-2
changes — don't hand-roll curl/ssh ad hoc when a script covers it. Add new ones as
needed (keep them sourcing `lib.sh`, never hardcode secrets). Secrets come from the
gitignored `terraform.tfvars`; `lib.sh` parses them.

## Facts

- Node name: `pve` (PVE 9.2.3). Host LAN IP `192.168.1.101`.
- Reached via Tailscale LXC `ortho-internal` (`100.100.70.50`), NPM forwards:
  - `:2222` → host `:22` (SSH, key `~/.ssh/proxmox_homelab`)
  - `:8009` → host `:8006` (API)
- Storage: `local-lvm` (lvm-thin, ~853 GB) for disks; `local` (dir) for images/
  templates/**snippets** (snippets enabled for cloud-init).
- Internal subnet `10.10.10.0/24` on bridge `vmbr1` (no uplink). Gateway/DNS =
  netservices LXC `10.10.10.1`.
- Git remote uses the `github.com-hassankhurram` SSH alias (not the default identity).

## Guests

| Guest | id | IP | vCPU | RAM | Disk |
|-------|----|----|------|-----|------|
| netservices (LXC) | 9001 | 10.10.10.1 | 2 | 1 GB | 8 GB |
| tailscale-alt (LXC) | 9002 | 10.10.10.50 | 1 | 512 MB | 8 GB |
| staging | 9010 | 10.10.10.10 | 4 | 8 GB | 120 GB |
| prod (Coolify) | 9020 | 10.10.10.20 | 6 | 16 GB | 120 GB |
| backup | 9030 | 10.10.10.30 | 2 | 8 GB | 120 GB |
| workplace | 9040 | 10.10.10.40 | 6 | 16 GB | 256 GB |

### Tailscale topology

- **netservices** (9001) = subnet router on **account A** (`hassankhurram`), advertises
  `10.10.10.0/24`. Set up by `netservices-bootstrap.sh` (authkey in tfvars).
- **tailscale-alt** (9002) = subnet router on a **different account B**, also advertises
  `10.10.10.0/24`. Tailscale installed **manually** (interactive login, no authkey).
  Reproduce with `scripts/tailscale-alt-setup.sh` run inside the CT. Root password in
  tfvars (`ts_alt_root_password`).
- Both nodes have the UDP-GRO-forwarding NIC tuning (`tailscale-nic-tune.service`) for
  better subnet-router throughput. Routes must be **approved per account** in each
  admin console before they go live.

## Layer boundary (do not cross)

- **Terraform** = infra: VMs, LXC, bridge, firewall, autostart. Day-0/1 only.
- **cloud-init** (`cloud-init/base.yaml.tftpl`) = in-guest base: zsh, docker, Coolify(prod).
- **Coolify** = app deploys: revisions, env, DBs, metrics. Terraform must NOT manage
  in-guest app churn — it will fight Coolify.

## Scripts

```
scripts/lib.sh                  shared config + helpers (pve_api, pve_ssh, pve_scp,
                                pve_token, ts_authkey). Source it; don't run.
scripts/preflight.sh            read-only health check (ports/API/SSH/snippets). Safe.
scripts/apply.sh <cmd> [--yes]  setup + updates. cmds:
                                  phase1   bridge + image downloads + netservices LXC
                                  bootstrap configure netservices over SSH (NAT/DNS/TS)
                                  phase2   the four VMs
                                  all      phase1 -> bootstrap -> phase2
                                  plan     terraform plan
                                  apply    full terraform apply (day-2 updates)
                                (mutating cmds are plan-only without --yes)
scripts/netservices-bootstrap.sh  runs INSIDE the netservices LXC: NAT + dnsmasq + tailscale
scripts/tailscale-alt-setup.sh    runs INSIDE the tailscale-alt LXC: subnet router on
                                  account B (interactive login) + NIC tuning
```

## Workflow

1. `./scripts/preflight.sh` — confirm reachability.
2. `./scripts/apply.sh phase1 --yes` — foundation.
3. `./scripts/apply.sh bootstrap` — bring up the router; then approve the
   `10.10.10.0/24` subnet route in the Tailscale admin console.
4. `./scripts/apply.sh phase2 --yes` — creates VMs, then auto-reboots them once.
   (Debian genericcloud renders the netplan static config on first boot but only
   *applies* it after a reboot — without the reboot, VMs come up with no network.
   `reboot-vms` does just this step if needed.)
5. Coolify on prod (`http://10.10.10.20:8000`); add staging/backup/workplace as
   remote servers.
6. Updates later: edit `.tf`, `./scripts/apply.sh plan`, then `apply --yes`.

## Ingress

Public VM (on tailnet) runs Caddy → Tailscale → internal services. Cloudflare DNS →
public VM. Planned upgrade: Cloudflare Tunnel (`cloudflared`) in an LXC, retire the
public VM's inbound role.

## Conventions

- Use non-deprecated bpg resource names (`proxmox_download_file`,
  `proxmox_network_linux_bridge`); reference the bridge resource (not the string var)
  so create-ordering is explicit.
- Never commit `terraform.tfvars` / state (gitignored).
- Run `terraform fmt` before committing (`.tf` only; tfvars is ignored).
