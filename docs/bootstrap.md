# Bootstrap

## 1. SSH key (already generated)

Public key `~/.ssh/proxmox_homelab.pub` must be in the host's
`/root/.ssh/authorized_keys`. On the host:

```sh
echo 'ssh-rsa AAAA... claude-proxmox-homelab-openclaw' >> /root/.ssh/authorized_keys
```

## 2. Proxmox API token for Terraform

On the host (or via the GUI: Datacenter → Permissions → API Tokens):

```sh
# A dedicated user + token, scoped to admin for now (tighten later).
pveum user add terraform@pve
pveum aclmod / -user terraform@pve -role Administrator
pveum user token add terraform@pve tf --privsep 0
# ^ prints the token VALUE once. Put it in terraform.tfvars as:
#   pve_api_token = "terraform@pve!tf=<that-uuid>"
```

> To least-privilege it later, create a custom role with only
> `VM.*`, `Datastore.*`, `SDN.*`, `Sys.Modify` and assign that instead of
> `Administrator`.

## 3. Apply

```sh
cp terraform.tfvars.example terraform.tfvars   # fill in
terraform init
terraform plan
terraform apply
```

## 4. Configure the netservices LXC (post-apply)

```sh
# from the host (or via the Proxmox MCP)
pct push 9001 scripts/netservices-bootstrap.sh /root/bootstrap.sh
pct exec 9001 -- bash /root/bootstrap.sh "tskey-auth-xxxx"
```

Then approve the `10.10.10.0/24` subnet route in the Tailscale admin console.

## 5. Coolify

Coolify auto-installs on prod via cloud-init. Once up:

- Dashboard: `http://10.10.10.20:8000` (over Tailscale).
- Add **staging** (`10.10.10.10`) and **backup** (`10.10.10.30`) as *remote servers*.
- Create `production` and `staging` environments.

## 6. Public ingress

On your public VM (on the tailnet): Caddy reverse-proxies the prod hostnames to
`http://10.10.10.20` over Tailscale. Cloudflare DNS → public VM. Later: swap to a
Cloudflare Tunnel (`cloudflared`) in an LXC and retire the public VM's inbound role.
