#!/usr/bin/env bash
# ==============================================================================
# Kubernetes Join Command & Certificate Key Generator
# ==============================================================================
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"

check_root
load_config "control-plane"

log_header "Kubernetes Cluster Join Commands & Tokens"

if ! command -v kubeadm >/dev/null 2>&1; then
    log_error "kubeadm is not installed on this system."
fi

# Generate worker join command
WORKER_JOIN_CMD=$(kubeadm token create --print-join-command 2>/dev/null || true)

# Upload certs for control plane join and retrieve key
CERT_KEY=$(kubeadm init phase upload-certs --upload-certs 2>/dev/null | tail -1 || true)

echo -e "${BOLD}Worker Join Command:${NC}"
echo -e "  sudo ${WORKER_JOIN_CMD}"
echo
echo -e "${BOLD}Control Plane Join Command (CP2 / CP3):${NC}"
echo -e "  sudo ${WORKER_JOIN_CMD} \\"
echo -e "      --control-plane \\"
echo -e "      --certificate-key ${CERT_KEY}"
echo
echo -e "${BOLD}--------------------------------------------------------------------${NC}"
echo -e "${BOLD}Using the Modular Installer Wrapper (k8s.sh):${NC}"
echo
echo -e "For Control Plane 2/3:"
echo -e "  sudo ROLE=control-plane-join \\"
echo -e "       CONTROL_PLANE_ENDPOINT=${CONTROL_PLANE_ENDPOINT:-<LB_ENDPOINT>} \\"
echo -e "       JOIN_TOKEN=<TOKEN> \\"
echo -e "       DISCOVERY_TOKEN_CA_CERT_HASH=<HASH> \\"
echo -e "       CERTIFICATE_KEY=${CERT_KEY} \\"
echo -e "       ./k8s.sh"
echo
echo -e "For Worker Nodes:"
echo -e "  sudo ROLE=worker \\"
echo -e "       CONTROL_PLANE_ENDPOINT=${CONTROL_PLANE_ENDPOINT:-<LB_ENDPOINT>} \\"
echo -e "       JOIN_TOKEN=<TOKEN> \\"
echo -e "       DISCOVERY_TOKEN_CA_CERT_HASH=<HASH> \\"
echo -e "       ./k8s.sh"
echo -e "${BOLD}--------------------------------------------------------------------${NC}"
