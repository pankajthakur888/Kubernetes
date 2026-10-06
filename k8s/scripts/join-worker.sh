#!/usr/bin/env bash
# ==============================================================================
# Worker Node Joiner (kubeadm join)
# ==============================================================================
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"

check_root
detect_os
detect_wsl
detect_node_ip
ROLE="worker"
load_config "${ROLE}"

# Run prerequisites, runtime, and package installers
"${SCRIPT_DIR}/install-prereqs.sh"
"${SCRIPT_DIR}/install-containerd.sh"
"${SCRIPT_DIR}/install-k8s-packages.sh"

[[ -n "${CONTROL_PLANE_ENDPOINT:-}" ]] || log_error "CONTROL_PLANE_ENDPOINT is required to join worker node."
[[ -n "${JOIN_TOKEN:-}" ]] || log_error "JOIN_TOKEN is required to join worker node."
[[ -n "${DISCOVERY_TOKEN_CA_CERT_HASH:-}" ]] || log_error "DISCOVERY_TOKEN_CA_CERT_HASH is required to join worker node."

CP_ENDPOINT="${CONTROL_PLANE_ENDPOINT}"
CP_PORT="${CONTROL_PLANE_PORT:-6443}"

log_header "Joining Worker Node to Cluster at ${CP_ENDPOINT}:${CP_PORT}"

JOIN_ARGS=()
JOIN_ARGS+=("${CP_ENDPOINT}:${CP_PORT}")
JOIN_ARGS+=(--token "${JOIN_TOKEN}")
JOIN_ARGS+=(--discovery-token-ca-cert-hash "${DISCOVERY_TOKEN_CA_CERT_HASH}")
JOIN_ARGS+=(--cri-socket="${CRI_SOCKET:-unix:///run/containerd/containerd.sock}")

if [[ -n "${KUBEADM_EXTRA_WORKER_ARGS:-}" ]]; then
    read -r -a EXTRA_ARRAY <<< "${KUBEADM_EXTRA_WORKER_ARGS}"
    JOIN_ARGS+=("${EXTRA_ARRAY[@]}")
fi

log_info "Executing kubeadm join for worker..."
kubeadm join "${JOIN_ARGS[@]}"

log_success "Worker node joined successfully! Check status from Control Plane: kubectl get nodes"
