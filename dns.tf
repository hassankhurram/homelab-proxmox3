# Homelab public DNS, split into two reachability tiers:
#
#  PRIVATE (tailnet-only): *.lab + lab -> A record to the internal IP (10.10.10.20,
#    Coolify's proxy on prod). Only resolvable+routable for devices on a Tailscale
#    tailnet that has the 10.10.10.0/24 subnet route approved. Never via jarvis.
#
#  PUBLIC (via jarvis NPM): production hostnames -> CNAME jarvis.hassankhurram.com,
#    where NPM terminates TLS and reverse-proxies over Tailscale to the homelab.

# --- Private (Tailscale-only) ---
# Point at tailscale-alt's node IP (shared into account A); its proxy routes by
# hostname to internal services. Reachable by any tailnet device — NO accept-routes.
resource "cloudflare_dns_record" "private" {
  # coolify lives at coolify.lab.* (covered by the *.lab wildcard A + cert)
  for_each = toset(["lab", "*.lab"])

  zone_id = var.cloudflare_zone_id
  name    = "${each.key}.${var.domain}"
  type    = "A"
  content = var.tailscale_alt_ip
  ttl     = 1
  proxied = false
  comment = "homelab PRIVATE (tailnet-only, terraform-managed)"
}

# --- Public (via jarvis) ---
# Add production hostnames to this set as they come online.
resource "cloudflare_dns_record" "public" {
  for_each = toset(var.public_hostnames)

  zone_id = var.cloudflare_zone_id
  name    = "${each.key}.${var.domain}"
  type    = "CNAME"
  content = var.public_vm_cname
  ttl     = 1
  proxied = false
  comment = "homelab PUBLIC via jarvis (terraform-managed)"
}
