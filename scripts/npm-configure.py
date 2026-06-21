#!/usr/bin/env python3
"""Configure an NPM instance (idempotent). Runs INSIDE the proxy container,
hitting NPM on 127.0.0.1:81. Bootstraps the default admin creds to the real
ones, requests a Cloudflare DNS-01 wildcard cert, and creates the proxy hosts.

Env:
  NPM_EMAIL, NPM_PASS   target admin creds
  CF_TOKEN              cloudflare api token (DNS-01)
Hosts are hardcoded for this homelab (coolify + *.lab -> Coolify on prod).
"""
import json, os, sys, time, urllib.request, urllib.error

NPM = os.environ.get("NPM_URL", "http://127.0.0.1:81")
EMAIL, PASS, CF = os.environ["NPM_EMAIL"], os.environ["NPM_PASS"], os.environ["CF_TOKEN"]
DOMAIN = "orthosuite.net"
PROD = "10.10.10.20"
CERT_NAME = "orthosuite-homelab"
DOMAINS = [f"lab.{DOMAIN}", f"*.lab.{DOMAIN}"]  # coolify.lab covered by *.lab


def api(method, path, body=None, token=None, timeout=120):
    data = json.dumps(body).encode() if body is not None else None
    h = {"Content-Type": "application/json"}
    if token:
        h["Authorization"] = f"Bearer {token}"
    r = urllib.request.Request(NPM + path, data=data, headers=h, method=method)
    try:
        with urllib.request.urlopen(r, timeout=timeout) as resp:
            return resp.status, json.load(resp)
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.load(e)
        except Exception:
            return e.code, {"raw": e.read().decode()[:300]}


def get_token(identity, secret):
    st, d = api("POST", "/api/tokens", {"identity": identity, "secret": secret})
    return d.get("token")


# 1. Bootstrap creds
token = get_token(EMAIL, PASS)
if not token:
    _, health = api("GET", "/api/")
    if health.get("setup") is False:
        print("NPM unconfigured -> creating first admin user")
        st, d = api("POST", "/api/users", {
            "name": "Admin", "nickname": "Admin", "email": EMAIL,
            "roles": ["admin"], "is_disabled": False,
            "auth": {"type": "password", "secret": PASS},
        })
        print("  create-user:", st, "ok" if st < 400 else d)
        token = get_token(EMAIL, PASS)
        if not token:  # some builds need the password set separately
            st, d = api("POST", "/api/users", {
                "name": "Admin", "nickname": "Admin", "email": EMAIL,
                "roles": ["admin"], "is_disabled": False}, )
            uid = (d or {}).get("id", 1)
            api("PUT", f"/api/users/{uid}/auth", {"type": "password", "secret": PASS})
            token = get_token(EMAIL, PASS)
    if not token:  # legacy default-creds path
        t = get_token("admin@example.com", "changedme")
        if t:
            api("PUT", "/api/users/1", {"name": "Admin", "nickname": "Admin", "email": EMAIL}, token=t)
            api("PUT", "/api/users/1/auth", {"type": "password", "current": "changedme", "secret": PASS}, token=t)
            token = get_token(EMAIL, PASS)
if not token:
    print("cannot log in"); sys.exit(1)
print("authenticated")

# 2. Wildcard DNS-01 cert (skip if present)
st, certs = api("GET", "/api/nginx/certificates", token=token)
cert = next((c for c in (certs or []) if c.get("nice_name") == CERT_NAME), None)
if cert:
    cert_id = cert["id"]; print(f"cert exists id={cert_id}")
else:
    print("requesting LE DNS-01 wildcard cert (~1-2 min)...")
    st, d = api("POST", "/api/nginx/certificates", {
        "provider": "letsencrypt", "nice_name": CERT_NAME, "domain_names": DOMAINS,
        "meta": {"dns_challenge": True, "dns_provider": "cloudflare",
                 "dns_provider_credentials": f"dns_cloudflare_api_token = {CF}",
                 "propagation_seconds": 30},
    }, token=token, timeout=300)
    if not d.get("id"):
        print("CERT FAILED:", st, d); sys.exit(1)
    cert_id = d["id"]; print(f"cert created id={cert_id}")

# 3. proxy hosts
st, hosts = api("GET", "/api/nginx/proxy-hosts", token=token)


def ensure(domains, port, label):
    cur = next((h for h in (hosts or []) if set(h["domain_names"]) == set(domains)), None)
    body = {"domain_names": domains, "forward_scheme": "http", "forward_host": PROD,
            "forward_port": port, "certificate_id": cert_id, "ssl_forced": True,
            "http2_support": True, "block_exploits": True, "allow_websocket_upgrade": True,
            "access_list_id": 0, "advanced_config": "", "locations": [],
            "meta": {"letsencrypt_agree": False, "dns_challenge": False}}
    if cur:
        api("PUT", f"/api/nginx/proxy-hosts/{cur['id']}", body, token=token)
        print(f"  updated {label}: {domains} -> {PROD}:{port}")
    else:
        st, d = api("POST", "/api/nginx/proxy-hosts", body, token=token)
        print(f"  {'created' if d.get('id') else 'FAILED'} {label}: {domains} -> {PROD}:{port}"
              + ("" if d.get("id") else f"  {st} {d}"))


ensure([f"coolify.lab.{DOMAIN}"], 8000, "coolify")
ensure([f"*.lab.{DOMAIN}"], 80, "wildcard-lab")

# remove the old bare coolify.<domain> proxy host if it exists (moved to coolify.lab)
old = next((h for h in (hosts or []) if h["domain_names"] == [f"coolify.{DOMAIN}"]), None)
if old:
    api("DELETE", f"/api/nginx/proxy-hosts/{old['id']}", token=token)
    print(f"  removed old host coolify.{DOMAIN}")
print("done")
