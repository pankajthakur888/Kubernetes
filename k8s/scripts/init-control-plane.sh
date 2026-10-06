#!/usr/bin/env bash
# ==============================================================================
# Primary Control Plane Initialization (CP1 with kubeadm init)
# ==============================================================================
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"

check_root
detect_os
detect_wsl
detect_node_ip
ROLE="control-plane"
load_config "${ROLE}"

# Run prerequisites, runtime, and package installers
"${SCRIPT_DIR}/install-prereqs.sh"
"${SCRIPT_DIR}/install-containerd.sh"
"${SCRIPT_DIR}/install-k8s-packages.sh"

log_header "Initializing Kubernetes Control Plane (Role: ${ROLE})"

# Determine control plane endpoint
CP_ENDPOINT="${CONTROL_PLANE_ENDPOINT:-${NODE_IP}}"
CP_PORT="${CONTROL_PLANE_PORT:-6443}"

# Compute SANs
ALL_SANS=$(format_apiserver_sans "${NODE_IP},127.0.0.1,localhost,${CP_ENDPOINT},${EXTRA_SANS:-}")

log_info "Configuring kubeadm init parameters:"
echo "  Control Plane Endpoint: ${CP_ENDPOINT}:${CP_PORT}"
echo "  Advertise Address:      ${NODE_IP}"
echo "  Pod Network CIDR:       ${POD_CIDR:-10.244.0.0/16}"
echo "  Service CIDR:           ${SERVICE_CIDR:-10.96.0.0/12}"
echo "  API Server SANs:        ${ALL_SANS}"

INIT_ARGS=()
INIT_ARGS+=(--control-plane-endpoint="${CP_ENDPOINT}:${CP_PORT}")
INIT_ARGS+=(--pod-network-cidr="${POD_CIDR:-10.244.0.0/16}")
INIT_ARGS+=(--service-cidr="${SERVICE_CIDR:-10.96.0.0/12}")
INIT_ARGS+=(--apiserver-advertise-address="${NODE_IP}")
INIT_ARGS+=(--apiserver-cert-extra-sans="${ALL_SANS}")
INIT_ARGS+=(--cri-socket="${CRI_SOCKET:-unix:///run/containerd/containerd.sock}")

if [[ "${UPLOAD_CERTS:-true}" == "true" ]]; then
    INIT_ARGS+=(--upload-certs)
fi

if [[ -n "${KUBEADM_EXTRA_INIT_ARGS:-}" ]]; then
    read -r -a EXTRA_ARRAY <<< "${KUBEADM_EXTRA_INIT_ARGS}"
    INIT_ARGS+=("${EXTRA_ARRAY[@]}")
fi

log_info "Executing kubeadm init..."
INIT_OUTPUT=$(kubeadm init "${INIT_ARGS[@]}")
echo "${INIT_OUTPUT}"

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

log_success "Kubernetes Control Plane 1 initialized successfully!"

# Save join command details
mkdir -p /etc/kubernetes/k8s-installer
echo "${INIT_OUTPUT}" > /etc/kubernetes/k8s-installer/init-output.txt

# Display join commands
"${SCRIPT_DIR}/token.sh"

# Install CNI if specified
if [[ -n "${CNI:-}" && "${CNI}" != "none" ]]; then
    "${SCRIPT_DIR}/install-cni.sh" "${CNI}"
fi
