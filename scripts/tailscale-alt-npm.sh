#!/usr/bin/env bash
# Install Docker + Nginx Proxy Manager on tailscale-alt (LXC 9002), the internal
# reverse proxy. tailscale-alt is on the internal subnet (reaches all VMs/LXC)
# and is shared into account A, so it serves both private (its own tailnet IP)
# and public (jarvis -> here) ingress. Run inside the container.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get update -qq
apt-get install -y -qq curl ca-certificates

command -v docker >/dev/null 2>&1 || curl -fsSL https://get.docker.com | sh

# Unprivileged LXC: overlay2 often won't work -> fall back to fuse-overlayfs.
if ! docker info >/dev/null 2>&1; then
  apt-get install -y -qq fuse-overlayfs
  mkdir -p /etc/docker
  echo '{"storage-driver":"fuse-overlayfs"}' >/etc/docker/daemon.json
  systemctl restart docker
  sleep 3
fi
docker info 2>/dev/null | grep -i "storage driver" || { journalctl -u docker --no-pager -n 25; exit 1; }

mkdir -p /opt/npm/data /opt/npm/letsencrypt
cat >/opt/npm/docker-compose.yml <<'YML'
services:
  npm:
    image: jc21/nginx-proxy-manager:latest
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
      - "100.100.70.20:81:81"   # admin/API only on the tailnet IP
    volumes:
      - ./data:/data
      - ./letsencrypt:/etc/letsencrypt
YML
cd /opt/npm && docker compose up -d
sleep 20
docker ps --format '{{.Names}} {{.Status}}' | grep -i npm && echo "NPM up" || { docker compose logs --tail 25; exit 1; }
