#!/usr/bin/env bash
set -euo pipefail
# Remove mdnest
if [ -f /opt/mdnest/docker-compose.yml ]; then
  (cd /opt/mdnest && docker compose down -v 2>/dev/null) || true
fi
docker rm -f $(docker ps -aq --filter "name=mdnest") 2>/dev/null || true
rm -rf /opt/mdnest

# Hello-world static site (nginx)
mkdir -p /opt/hello
cat > /opt/hello/index.html <<'HTML'
<!doctype html>
<html><head><meta charset="utf-8"><title>Hello — orthosuite homelab</title></head>
<body style="font-family:system-ui,sans-serif;text-align:center;padding:5rem;background:#0b1020;color:#e6e9f0">
  <h1>👋 Hello from the homelab</h1>
  <p>Static site · nginx · LXC 9003 (10.10.10.60)</p>
  <p>Internet → Cloudflare → jarvis → Tailscale → here</p>
</body></html>
HTML

docker rm -f hello 2>/dev/null || true
docker run -d --name hello --restart unless-stopped -p 8080:80 \
  -v /opt/hello:/usr/share/nginx/html:ro nginx:alpine
sleep 3
docker ps --format '{{.Names}} {{.Status}}' | grep hello
curl -s -o /dev/null -w "local hello: %{http_code}\n" http://127.0.0.1:8080/
