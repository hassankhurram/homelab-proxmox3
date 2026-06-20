#!/usr/bin/env bash
# Setup + update orchestration. Mutating apply steps require --yes (else plan-only).
#
# Usage:
#   apply.sh phase1   [--yes]   # bridge + image downloads + netservices LXC
#   apply.sh bootstrap          # configure netservices (NAT/dnsmasq/tailscale) over SSH
#   apply.sh phase2   [--yes]   # the four VMs (cloud-init needs phase1+bootstrap first)
#   apply.sh all      [--yes]   # phase1 -> bootstrap -> phase2
#   apply.sh plan               # terraform plan (read-only)
#   apply.sh apply    [--yes]   # full terraform apply (day-2 updates)
. "$(dirname "$0")/lib.sh"
cd "$REPO_DIR"

CMD="${1:-}"; YES=""; [ "${2:-}" = "--yes" ] && YES="-auto-approve"

PHASE1_TARGETS=(
  -target=proxmox_network_linux_bridge.internal
  -target=proxmox_download_file.debian_lxc
  -target=proxmox_download_file.debian_cloud
  -target=proxmox_virtual_environment_container.netservices
)

tf_apply() { # tf_apply <description> [extra terraform args...]
  local desc="$1"; shift
  say "$desc"
  if [ -n "$YES" ]; then
    terraform apply -auto-approve "$@"
  else
    terraform plan "$@"
    echo; echo "Plan only. Re-run with --yes to apply."
  fi
}

bootstrap_netservices() {
  say "Bootstrapping netservices LXC ($NETSERVICES_VMID): NAT + dnsmasq + tailscale"
  local key; key="$(ts_authkey)"
  [ -n "$key" ] || die "tailscale_authkey not found in terraform.tfvars"
  pve_scp "$REPO_DIR/scripts/netservices-bootstrap.sh" /tmp/ns-bootstrap.sh
  pve_ssh "pct push $NETSERVICES_VMID /tmp/ns-bootstrap.sh /root/bootstrap.sh && pct exec $NETSERVICES_VMID -- bash /root/bootstrap.sh '$key'"
  ok "netservices bootstrapped — approve the 10.10.10.0/24 route in the Tailscale admin console"
}

case "$CMD" in
  phase1)    tf_apply "Phase 1: foundation" "${PHASE1_TARGETS[@]}" ;;
  bootstrap) bootstrap_netservices ;;
  phase2)    tf_apply "Phase 2: VMs" ;;
  all)       YES="-auto-approve"; tf_apply "Phase 1" "${PHASE1_TARGETS[@]}"; bootstrap_netservices; tf_apply "Phase 2" ;;
  plan)      terraform plan ;;
  apply)     tf_apply "Full apply (updates)" ;;
  *)         sed -n '2,12p' "$0"; exit 1 ;;
esac
