#!/usr/bin/env bash
set -Eeuo pipefail

################################################################################
# Universal Kubernetes (kubeadm / containerd) Modular Installer
#
# Supported Operating Systems:
#   Ubuntu, Debian, RHEL, Rocky Linux, AlmaLinux, CentOS Stream, Amazon Linux
#
# Supported Environments:
#   onprem, aws, gcp, azure
#
# Roles:
#   control-plane, control-plane-join, worker
################################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/scripts/common.sh"

# Resolve action from argument or ROLE environment variable
ACTION="${1:-${ROLE:-help}}"

# Show help without requiring root
if [[ "${ACTION}" == "help" || "${ACTION}" == "--help" || "${ACTION}" == "-h" ]]; then
    echo -e "
${BOLD}Kubernetes Universal Modular Installer (kubeadm / containerd)${NC}

${BOLD}Usage:${NC}
  sudo ./k8s.sh <command> [options]

${BOLD}Commands:${NC}
  control-plane       Initialize the primary control plane (CP1 with kubeadm init)
  control-plane-join  Join an additional control plane (CP2 / CP3) to the cluster
  worker              Join a worker node to the cluster
  prereqs             Install kernel modules, sysctl tuning, packages, and firewall
  containerd          Install and configure containerd with SystemdCgroup=true
  packages            Configure official pkgs.k8s.io repository and install kubelet/kubeadm/kubectl
  token               Display cluster join commands and upload certs key
  health-check        Run diagnostic check on nodes, static pods, and CoreDNS
  cni [calico|cilium] Install Calico or Cilium CNI
  csi                 Install CSI storage driver (Local-Path onprem / Cloud CSI)
  metallb [pool]      Install MetalLB bare-metal LoadBalancer
  lb <cp1> <cp2> <cp3> Setup HAProxy load balancer across control plane nodes
  reset [--purge-iptables] Run kubeadm reset and clean network interfaces

${BOLD}Backward-Compatible Environment Variable Syntax:${NC}
  sudo ROLE=control-plane \\
       ENVIRONMENT=onprem \\
       CONTROL_PLANE_ENDPOINT=k8s-api.example.com \\
       NODE_IP=10.10.10.11 \\
       CNI=calico \\
       ./k8s.sh

  sudo ROLE=control-plane-join \\
       CONTROL_PLANE_ENDPOINT=k8s-api.example.com \\
       NODE_IP=10.10.10.12 \\
       JOIN_TOKEN=<TOKEN> \\
       DISCOVERY_TOKEN_CA_CERT_HASH=<HASH> \\
       CERTIFICATE_KEY=<KEY> \\
       ./k8s.sh

  sudo ROLE=worker \\
       CONTROL_PLANE_ENDPOINT=k8s-api.example.com \\
       JOIN_TOKEN=<TOKEN> \\
       DISCOVERY_TOKEN_CA_CERT_HASH=<HASH> \\
       ./k8s.sh

${BOLD}Configuration Files:${NC}
  config/cluster.env        Global settings (version, endpoint, CIDRs, CNI)
  config/control-plane.env   Control plane settings (SANs, taints, advertise IP)
  config/worker.env          Worker node settings (labels, taints)
"
    exit 0
fi

check_root

# Sourcing configs
load_config "${ROLE:-${1:-}}"

case "${ACTION}" in
    control-plane|bootstrap|init)
        "${SCRIPT_DIR}/scripts/init-control-plane.sh"
        ;;
    control-plane-join|join-cp)
        "${SCRIPT_DIR}/scripts/join-control-plane.sh"
        ;;
    worker|join-worker)
        "${SCRIPT_DIR}/scripts/join-worker.sh"
        ;;
    prereqs)
        "${SCRIPT_DIR}/scripts/install-prereqs.sh"
        ;;
    containerd)
        "${SCRIPT_DIR}/scripts/install-containerd.sh"
        ;;
    packages)
        "${SCRIPT_DIR}/scripts/install-k8s-packages.sh"
        ;;
    token)
        "${SCRIPT_DIR}/scripts/token.sh"
        ;;
    health-check|status)
        "${SCRIPT_DIR}/scripts/health-check.sh"
        ;;
    cni)
        "${SCRIPT_DIR}/scripts/install-cni.sh" "${2:-}"
        ;;
    csi)
        "${SCRIPT_DIR}/scripts/install-csi.sh"
        ;;
    metallb)
        "${SCRIPT_DIR}/scripts/install-metallb.sh" "${2:-}"
        ;;
    lb)
        "${SCRIPT_DIR}/scripts/setup-lb.sh" "${2:-}" "${3:-}" "${4:-}"
        ;;
    reset|uninstall)
        "${SCRIPT_DIR}/uninstall.sh" "${2:-}"
        ;;
    *)
        log_error "Unknown command '${ACTION}'. Run './k8s.sh help' for usage instructions."
        ;;
esac
