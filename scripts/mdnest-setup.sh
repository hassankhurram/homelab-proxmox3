#!/usr/bin/env bash
# Install Docker + clone mdnest + generate its config (inside the mdnest LXC 9003).
# Run a SECOND pass (mdnest-server rebuild) after mdnest.conf is edited.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get update -qq
apt-get install -y -qq git curl ca-certificates

command -v docker >/dev/null 2>&1 || curl -fsSL https://get.docker.com | sh
if ! docker info >/dev/null 2>&1; then
  apt-get install -y -qq fuse-overlayfs
  mkdir -p /etc/docker
  echo '{"storage-driver":"fuse-overlayfs"}' >/etc/docker/daemon.json
  systemctl restart docker
  sleep 3
fi
docker info >/dev/null 2>&1 || { journalctl -u docker --no-pager -n 20; exit 1; }

cd /opt
[ -d mdnest ] || git clone https://github.com/mahsanamin/mdnest.git
cd mdnest
[ -f mdnest.conf ] || ./mdnest-server setup
echo "=== mdnest.conf (generated) ==="
cat mdnest.conf
