#!/usr/bin/env bash
# ==============================================================================
# Cluster Token and Connection Helper
# ==============================================================================
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"

detect_node_ip
load_config "server"

TOKEN_FILE="/var/lib/rancher/k3s/server/node-token"

if [[ ! -f "${TOKEN_FILE}" ]]; then
    log_error "Token file not found at ${TOKEN_FILE}. Is K3s server installed on this node?"
fi

TOKEN=$(cat "${TOKEN_FILE}")
API_ENDPOINT="${API_LB_ENDPOINT:-${NODE_IP}}"
API_URL="https://${API_ENDPOINT}:6443"

log_header "K3s Cluster Connection Details"

echo -e "${BOLD}Cluster API Server:${NC} ${CYAN}${API_URL}${NC}"
echo -e "${BOLD}Join Token:${NC}         ${YELLOW}${TOKEN}${NC}"
echo -e "${BOLD}Kubeconfig Path:${NC}    /etc/rancher/k3s/k3s.yaml"
echo
echo -e "${BOLD}--------------------------------------------------------------------${NC}"
echo -e "${BOLD}Join Additional Control Plane (CP2 / CP3):${NC}"
echo -e "  sudo ROLE=server-join K3S_URL=${API_URL} K3S_TOKEN="${TOKEN}" ./k3s.sh"
echo
echo -e "${BOLD}Join Worker Node:${NC}"
echo -e "  sudo ROLE=worker K3S_URL=${API_URL} K3S_TOKEN="${TOKEN}" ./k3s.sh"
echo -e "${BOLD}--------------------------------------------------------------------${NC}"
echo
