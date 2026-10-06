#!/usr/bin/env bash
# ==============================================================================
# Control Plane Installer & Cluster Initializer
# ==============================================================================
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"

check_root
detect_os
detect_wsl
detect_node_ip

MODE="${1:-init}"  # 'init' for CP1, 'join' for CP2/CP3
ROLE="server-${MODE}"
load_config "${ROLE}"

# Run host preparation
"${SCRIPT_DIR}/install.sh"

log_header "Installing K3s Control-Plane (Role: ${ROLE})"

INSTALL_ARGS="server"
INSTALL_ARGS+=" --write-kubeconfig-mode=${KUBECONFIG_MODE:-644}"
INSTALL_ARGS+=" --node-ip=${NODE_IP}"
INSTALL_ARGS+=" --node-name=${NODE_NAME:-$(hostname -s)}"
INSTALL_ARGS+=" --cluster-cidr=${CLUSTER_CIDR:-10.42.0.0/16}"
INSTALL_ARGS+=" --service-cidr=${SERVICE_CIDR:-10.43.0.0/16}"
INSTALL_ARGS+=" --cluster-dns=${CLUSTER_DNS:-10.43.0.10}"

# TLS SANs
SAN_FLAGS=$(format_san_flags "${NODE_IP},127.0.0.1,localhost,${API_LB_ENDPOINT:-},${TLS_SANS:-}")
INSTALL_ARGS+="${SAN_FLAGS}"

# CNI configuration
case "${CNI_PLUGIN:-flannel}" in
    flannel)
        log_info "Using default embedded Flannel CNI"
        ;;
    calico|cilium|none)
        log_warn "Disabling embedded Flannel & network policy to support ${CNI_PLUGIN} CNI"
        INSTALL_ARGS+=" --flannel-backend=none --disable-network-policy"
        ;;
    *)
        log_warn "Unknown CNI_PLUGIN '${CNI_PLUGIN}', using default"
        ;;
esac

# Component toggles
[[ "${DISABLE_TRAEFIK:-false}" == "true" ]] && INSTALL_ARGS+=" --disable=traefik"
[[ "${DISABLE_SERVICELB:-false}" == "true" ]] && INSTALL_ARGS+=" --disable=servicelb"
[[ "${DISABLE_LOCAL_STORAGE:-false}" == "true" ]] && INSTALL_ARGS+=" --disable=local-storage"
[[ "${DISABLE_METRICS_SERVER:-false}" == "true" ]] && INSTALL_ARGS+=" --disable=metrics-server"

# etcd backup configuration
INSTALL_ARGS+=" --etcd-snapshot-schedule-cron=${ETCD_SNAPSHOT_SCHEDULE:-0 */12 * * *}"
INSTALL_ARGS+=" --etcd-snapshot-retention=${ETCD_SNAPSHOT_RETENTION:-5}"
INSTALL_ARGS+=" --etcd-snapshot-dir=${ETCD_SNAPSHOT_DIR:-/var/lib/rancher/k3s/server/db/snapshots}"

if [[ "${ETCD_EXPOSE_METRICS:-false}" == "true" ]]; then
    INSTALL_ARGS+=" --etcd-expose-metrics=true"
fi

# Labels and Taints
if [[ -n "${SERVER_NODE_LABELS:-}" ]]; then
    INSTALL_ARGS+=$(format_label_flags "${SERVER_NODE_LABELS}")
fi
if [[ -n "${SERVER_NODE_TAINTS:-}" ]]; then
    INSTALL_ARGS+=$(format_taint_flags "${SERVER_NODE_TAINTS}")
fi

# Append extra args
if [[ -n "${SERVER_EXTRA_ARGS:-}" ]]; then
    INSTALL_ARGS+=" ${SERVER_EXTRA_ARGS}"
fi

export INSTALL_K3S_EXEC="${INSTALL_ARGS}"
if [[ "${K3S_VERSION:-stable}" != "stable" ]]; then
    export INSTALL_K3S_VERSION="${K3S_VERSION}"
fi

if [[ "${MODE}" == "init" ]]; then
    log_info "Initializing Primary Control Plane (etcd cluster leader)..."
    export INSTALL_K3S_EXEC="${INSTALL_ARGS} --cluster-init"
    curl -sfL https://get.k3s.io | sh -
else
    [[ -n "${K3S_URL:-}" ]] || log_error "K3S_URL is required to join an existing control plane."
    [[ -n "${K3S_TOKEN:-}" ]] || log_error "K3S_TOKEN is required to join an existing control plane."
    log_info "Joining existing control plane at ${K3S_URL}..."
    export K3S_URL="${K3S_URL}"
    export K3S_TOKEN="${K3S_TOKEN}"
    curl -sfL https://get.k3s.io | sh -
fi

log_info "Ensuring k3s service is active..."
systemctl enable k3s
systemctl restart k3s

log_info "Waiting for Kubernetes API server to become ready..."
ATTEMPTS=0
MAX_ATTEMPTS=30
until k3s kubectl get nodes >/dev/null 2>&1 || [[ ${ATTEMPTS} -ge ${MAX_ATTEMPTS} ]]; do
    sleep 2
    ATTEMPTS=$((ATTEMPTS + 1))
done

if [[ ${ATTEMPTS} -ge ${MAX_ATTEMPTS} ]]; then
    log_warn "API server took longer than expected to report ready. Check 'journalctl -u k3s -f'"
else
    log_success "Control plane node is active and ready!"
fi

# Set up user environment shortcuts if desired
if ! grep -q "alias k='k3s kubectl'" /etc/bash.bashrc 2>/dev/null; then
    echo "alias k='k3s kubectl'" >> /etc/bash.bashrc || true
    echo "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml" >> /etc/bash.bashrc || true
fi

# Print cluster connection tokens
"${SCRIPT_DIR}/token.sh"
