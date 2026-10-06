#!/usr/bin/env bash
# ==============================================================================
# Secondary Control Plane Joiner (CP2 / CP3 with kubeadm join --control-plane)
# ==============================================================================
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"

check_root
detect_os
detect_wsl
detect_node_ip
ROLE="control-plane-join"
load_config "${ROLE}"

# Run prerequisites, runtime, and package installers
"${SCRIPT_DIR}/install-prereqs.sh"
"${SCRIPT_DIR}/install-containerd.sh"
"${SCRIPT_DIR}/install-k8s-packages.sh"

[[ -n "${CONTROL_PLANE_ENDPOINT:-}" ]] || log_error "CONTROL_PLANE_ENDPOINT is required to join control plane."
[[ -n "${JOIN_TOKEN:-}" ]] || log_error "JOIN_TOKEN is required to join control plane."
[[ -n "${DISCOVERY_TOKEN_CA_CERT_HASH:-}" ]] || log_error "DISCOVERY_TOKEN_CA_CERT_HASH is required to join control plane."
[[ -n "${CERTIFICATE_KEY:-}" ]] || log_error "CERTIFICATE_KEY is required to join control plane."

CP_ENDPOINT="${CONTROL_PLANE_ENDPOINT}"
CP_PORT="${CONTROL_PLANE_PORT:-6443}"

log_header "Joining Control Plane to Cluster at ${CP_ENDPOINT}:${CP_PORT}"

JOIN_ARGS=()
JOIN_ARGS+=("${CP_ENDPOINT}:${CP_PORT}")
JOIN_ARGS+=(--token "${JOIN_TOKEN}")
JOIN_ARGS+=(--discovery-token-ca-cert-hash "${DISCOVERY_TOKEN_CA_CERT_HASH}")
JOIN_ARGS+=(--control-plane)
JOIN_ARGS+=(--certificate-key "${CERTIFICATE_KEY}")
JOIN_ARGS+=(--apiserver-advertise-address="${NODE_IP}")
JOIN_ARGS+=(--cri-socket="${CRI_SOCKET:-unix:///run/containerd/containerd.sock}")

if [[ -n "${KUBEADM_EXTRA_JOIN_ARGS:-}" ]]; then
    read -r -a EXTRA_ARRAY <<< "${KUBEADM_EXTRA_JOIN_ARGS}"
    JOIN_ARGS+=("${EXTRA_ARRAY[@]}")
fi

log_info "Executing kubeadm join --control-plane..."
kubeadm join "${JOIN_ARGS[@]}"

# Set up local kubeconfig
mkdir -p "${HOME}/.kube" /root/.kube
cp -f /etc/kubernetes/admin.conf "${HOME}/.kube/config" 2>/dev/null || true
cp -f /etc/kubernetes/admin.conf /root/.kube/config 2>/dev/null || true
if [[ -n "${SUDO_USER:-}" ]]; then
    USER_HOME=$(getent passwd "${SUDO_USER}" | cut -d: -f6)
    mkdir -p "${USER_HOME}/.kube"
    cp -f /etc/kubernetes/admin.conf "${USER_HOME}/.kube/config"
    chown -R "${SUDO_USER}:${SUDO_USER}" "${USER_HOME}/.kube"
fi

log_success "Control plane joined successfully!"
