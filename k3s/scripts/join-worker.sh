#!/usr/bin/env bash
# ==============================================================================
# Worker Node Joiner
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

# Run host preparation
"${SCRIPT_DIR}/install.sh"

# Pre-flight check: ensure conflicting server service is stopped
if systemctl is-active --quiet k3s 2>/dev/null; then
    log_warn "Conflicting 'k3s' (server) service is currently running."
    log_info "Stopping and disabling 'k3s' to prevent supervisor port (6444) conflict..."
    systemctl stop k3s 2>/dev/null || true
    systemctl disable k3s 2>/dev/null || true
fi

[[ -n "${K3S_URL:-}" ]] || log_error "K3S_URL is required for worker node."
[[ -n "${K3S_TOKEN:-}" ]] || log_error "K3S_TOKEN is required for worker node."

log_header "Joining K3s Worker Node to Cluster"

AGENT_ARGS="agent"
AGENT_ARGS+=" --node-ip=${NODE_IP}"
AGENT_ARGS+=" --node-name=${NODE_NAME:-$(hostname -s)}"

# Labels and Taints
if [[ -n "${WORKER_NODE_LABELS:-}" ]]; then
    AGENT_ARGS+=$(format_label_flags "${WORKER_NODE_LABELS}")
fi
if [[ -n "${WORKER_NODE_TAINTS:-}" ]]; then
    AGENT_ARGS+=$(format_taint_flags "${WORKER_NODE_TAINTS}")
fi

# Extra arguments
if [[ -n "${WORKER_EXTRA_ARGS:-}" ]]; then
    AGENT_ARGS+=" ${WORKER_EXTRA_ARGS}"
fi

export K3S_URL="${K3S_URL}"
export K3S_TOKEN="${K3S_TOKEN}"
export INSTALL_K3S_EXEC="${AGENT_ARGS}"
if [[ "${K3S_VERSION:-stable}" != "stable" ]]; then
    export INSTALL_K3S_VERSION="${K3S_VERSION}"
fi

log_info "Installing k3s-agent and connecting to ${K3S_URL}..."
curl -sfL https://get.k3s.io | sh -

systemctl enable k3s-agent
systemctl restart k3s-agent

log_info "Verifying k3s-agent service..."
sleep 5
if systemctl is-active --quiet k3s-agent; then
    log_success "Worker node successfully connected and running!"
    echo "Check node status from any Control Plane node via: kubectl get nodes -o wide"
else
    log_error "k3s-agent service failed to start. Review 'journalctl -u k3s-agent -f'"
fi
