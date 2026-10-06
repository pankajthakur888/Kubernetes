#!/usr/bin/env bash
set -Eeuo pipefail

################################################################################
# Universal K3s Modular Lab & Production Installer
# Supports:
#   Ubuntu / Debian
#   RHEL / Rocky / Alma / CentOS / Fedora
#   Windows via WSL2
################################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/scripts/common.sh"

# Resolve action from argument or ROLE environment variable
ACTION="${1:-${ROLE:-help}}"

# Show help without requiring root
if [[ "${ACTION}" == "help" || "${ACTION}" == "--help" || "${ACTION}" == "-h" ]]; then
    echo -e "
${BOLD}K3s Universal Lab & Production Installer${NC}

${BOLD}Usage:${NC}
  sudo ./k3s.sh <command> [options]

${BOLD}Commands:${NC}
  server-init        Initialize the primary control plane (CP1 with embedded etcd)
  server-join        Join an additional control plane node (CP2 / CP3) to etcd
  worker             Join a worker node to the cluster
  prereqs            Run host preparation and prerequisite package installations
  token              Display cluster join token, external IP, and copy-paste commands
  health-check       Run deep diagnostic check on nodes, pods, etcd, and DNS
  cni [calico|cilium] Install Calico or Cilium CNI
  metallb [pool]     Install and configure MetalLB with an IP range
  ingress [nginx]    Install Ingress-NGINX or configure Traefik
  lb <cp1> <cp2> <cp3> Setup HAProxy load balancer across control plane nodes
  uninstall [--purge-iptables] Tear down K3s and purge leftover networking/storage

${BOLD}Backward-Compatible Environment Variable Syntax:${NC}
  sudo ROLE=server-init ./k3s.sh
  sudo ROLE=server-join K3S_URL=https://<LB_OR_CP1>:6443 K3S_TOKEN=<TOKEN> ./k3s.sh
  sudo ROLE=worker K3S_URL=https://<LB_OR_CP1>:6443 K3S_TOKEN=<TOKEN> ./k3s.sh

${BOLD}Configuration Files:${NC}
  config/cluster.env  Global settings (version, CNI, VIP, CIDRs)
  config/server.env   Control plane settings (labels, taints, etcd snapshots)
  config/worker.env   Worker settings (labels, taints, extra flags)
"
    exit 0
fi

check_root

# Sourcing configs
load_config "${ROLE:-${1:-}}"

case "${ACTION}" in
    server-init|init)
        "${SCRIPT_DIR}/scripts/join-server.sh" "init"
        ;;
    server-join|join-server)
        "${SCRIPT_DIR}/scripts/join-server.sh" "join"
        ;;
    worker|join-worker)
        "${SCRIPT_DIR}/scripts/join-worker.sh"
        ;;
    token)
        "${SCRIPT_DIR}/scripts/token.sh"
        ;;
    health-check|status)
        "${SCRIPT_DIR}/scripts/health-check.sh"
        ;;
    prereqs|prepare)
        "${SCRIPT_DIR}/scripts/install.sh"
        ;;
    cni)
        "${SCRIPT_DIR}/scripts/install-cni.sh" "${2:-}"
        ;;
    metallb)
        "${SCRIPT_DIR}/scripts/install-metallb.sh" "${2:-}"
        ;;
    ingress)
        "${SCRIPT_DIR}/scripts/install-ingress.sh" "${2:-}"
        ;;
    lb)
        "${SCRIPT_DIR}/scripts/setup-lb.sh" "${2:-}" "${3:-}" "${4:-}"
        ;;
    uninstall)
        "${SCRIPT_DIR}/uninstall.sh" "${2:-}"
        ;;
    *)
        log_error "Unknown command '${ACTION}'. Run './k3s.sh help' for usage instructions."
        ;;
esac
