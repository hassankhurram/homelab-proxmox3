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
| tailscale-alt (LXC) | 9002 | 10.10.10.50 | 2 | 2 GB | 8 GB |
| mdnest (LXC) | 9003 | 10.10.10.60 | 2 | 2 GB | 20 GB |
| staging | 9010 | 10.10.10.10 | 4 | 8 GB | 120 GB |
| prod (Coolify) | 9020 | 10.10.10.20 | 6 | 16 GB | 120 GB |
| backup | 9030 | 10.10.10.30 | 2 | 8 GB | 120 GB |
| workplace | 9040 | 10.10.10.40 | 6 | 16 GB | 256 GB |

### Tailscale topology / ingress model

No subnet routes are needed by client devices — access is via a **proxy-on-node** that's
directly on the internal subnet, reached by its Tailscale IP.

- **tailscale-alt** (9002) — the **internal reverse proxy**. Account B (`orthosuiteihc`),
  IP **`100.100.70.20`**, also `10.10.10.50` on the internal bridge (so it reaches every
  VM/LXC directly). Runs **NPM** (Docker) with a wildcard LE cert (Cloudflare DNS-01).
  **Shared into account A**, so both `jarvis` and personal account-A devices reach it by
  its node IP — no `accept-routes`, nothing touches device routing tables. Account-B ACL
  + the share govern access. NPM admin on `100.100.70.20:81`.
- **netservices** (9001, account A) — router/NAT/dnsmasq for the VMs' internet; still
  advertises `10.10.10.0/24` but that route is **optional** now (proxy model supersedes it).
- **jarvis-orthosuite-b** — a 2nd tailscaled (Docker, `--network=host`) on jarvis joining
  account B with `--accept-routes`. Kept for a future plan to drop the account-A dependency.
- **ortho-internal** (`100.100.70.50`) — SSH backdoor to the Proxmox host (`:2222`→`:22`).
  Independent of all routing; do not disturb.

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
scripts/tailscale-alt-setup.sh    runs INSIDE tailscale-alt: join account B (interactive)
scripts/tailscale-alt-npm.sh      runs INSIDE tailscale-alt: install Docker + NPM
scripts/npm-configure.py          runs INSIDE the proxy CT: bootstrap NPM admin, request
                                  wildcard DNS-01 cert, create proxy hosts (env: NPM_URL,
                                  NPM_EMAIL, NPM_PASS, CF_TOKEN)
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

## Ingress (two tiers, both terminate on tailscale-alt's NPM)

- **PRIVATE (tailnet-only)**: `coolify.orthosuite.net`, `*.lab.orthosuite.net` → **A-record
  to `100.100.70.20`** (tailscale-alt). Reachable by any device whose Tailscale user has
  tailscale-alt shared + an ACL grant. NPM routes by host → Coolify (`:8000`) / apps
  (`:80`). Wildcard TLS via Cloudflare DNS-01.
- **PUBLIC (production)**: `var.public_hostnames` → **CNAME `jarvis.hassankhurram.com`** (DNS-only).
  jarvis (account A, public IP `51.159.67.59`, its own NPM at `100.100.15.130:81`) terminates
  TLS (HTTP-01 LE) and forwards to the internal backend, which it reaches via its
  **`tailscale-b`** route (account B, `--accept-routes`). Add a public host with
  `scripts/jarvis-public-host.py` (env: NPM_URL, NPM_EMAIL, NPM_PASS, PUB_HOST, FWD_HOST,
  FWD_PORT). Proven: `test.orthosuite.net` → `jarvis` → `10.10.10.60:3236` (mdnest) → 200.
- DNS managed in Terraform (`dns.tf`, `cloudflare_dns_record.private` / `.public`).
- All migrated zone records are DNS-only (un-proxied) to match pre-Cloudflare behavior.

NPM proxy hosts on tailscale-alt (one shared `*.lab` wildcard cert):
- `coolify.lab.orthosuite.net` → `10.10.10.20:8000`  (Coolify UI, prod)
- `*.lab.orthosuite.net`       → `10.10.10.20:80`     (Coolify Traefik → apps)
- `mdnest.lab.orthosuite.net`  → `10.10.10.60:3236`   (mdnest notes, LXC 9003)

Configure NPM with `scripts/npm-configure.py` (edit the `ensure(...)` calls). mdnest is
docker-compose based (`scripts/mdnest-setup.sh` installs Docker + clones + generates conf;
then edit `/opt/mdnest/mdnest.conf` and `./mdnest-server rebuild`). Key conf: `AUTH_MODE`
(single/multi), `BIND_ADDRESS=0.0.0.0` (so NPM can reach it), `MOUNT_<name>=<path>`.

## Conventions

- Use non-deprecated bpg resource names (`proxmox_download_file`,
  `proxmox_network_linux_bridge`); reference the bridge resource (not the string var)
  so create-ordering is explicit.
- Never commit `terraform.tfvars` / state (gitignored).
- Run `terraform fmt` before committing (`.tf` only; tfvars is ignored).
