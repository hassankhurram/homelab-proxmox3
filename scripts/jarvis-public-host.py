#!/usr/bin/env python3
"""Add/update a PUBLIC proxy host on jarvis's NPM with an HTTP-01 LE cert,
forwarding to an internal homelab host:port (reached via jarvis's tailscale-b
route). Run on jarvis (reaches its own NPM at 100.100.15.130:81).

Env: NPM_URL, NPM_EMAIL, NPM_PASS, PUB_HOST, FWD_HOST, FWD_PORT
"""
import json, os, sys, urllib.request, urllib.error

NPM = os.environ.get("NPM_URL", "http://100.100.15.130:81")
HOST, FH, FP = os.environ["PUB_HOST"], os.environ["FWD_HOST"], int(os.environ["FWD_PORT"])


def api(m, p, b=None, t=None, timeout=300):
    d = json.dumps(b).encode() if b is not None else None
    h = {"Content-Type": "application/json"}
    if t:
        h["Authorization"] = "Bearer " + t
    r = urllib.request.Request(NPM + p, data=d, headers=h, method=m)
    try:
        with urllib.request.urlopen(r, timeout=timeout) as x:
            return x.status, json.load(x)
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.load(e)
        except Exception:
            return e.code, {}


_, d = api("POST", "/api/tokens", {"identity": os.environ["NPM_EMAIL"], "secret": os.environ["NPM_PASS"]})
tok = d.get("token")
assert tok, f"login failed: {d}"

_, certs = api("GET", "/api/nginx/certificates", t=tok)
c = next((c for c in certs if c.get("provider") == "letsencrypt" and HOST in c.get("domain_names", [])), None)
if c:
    cid = c["id"]; print(f"cert exists id={cid}")
else:
    print(f"requesting HTTP-01 cert for {HOST} ...")
    st, d = api("POST", "/api/nginx/certificates",
                {"provider": "letsencrypt", "nice_name": HOST, "domain_names": [HOST], "meta": {}}, t=tok)
    cid = d.get("id")
    print("cert:", st, cid if cid else d)
    if not cid:
        sys.exit(1)

_, hosts = api("GET", "/api/nginx/proxy-hosts", t=tok)
cur = next((h for h in hosts if h["domain_names"] == [HOST]), None)
body = {"domain_names": [HOST], "forward_scheme": "http", "forward_host": FH, "forward_port": FP,
        "certificate_id": cid, "ssl_forced": True, "http2_support": True, "block_exploits": True,
        "allow_websocket_upgrade": True, "access_list_id": 0, "advanced_config": "", "locations": [],
        "meta": {"letsencrypt_agree": False, "dns_challenge": False}}
if cur:
    api("PUT", f"/api/nginx/proxy-hosts/{cur['id']}", body, t=tok); print(f"updated {HOST} -> {FH}:{FP}")
else:
    st, d = api("POST", "/api/nginx/proxy-hosts", body, t=tok)
    print(f"{'created' if d.get('id') else 'FAILED'} {HOST} -> {FH}:{FP}" + ("" if d.get("id") else f"  {st} {d}"))
print("done")
