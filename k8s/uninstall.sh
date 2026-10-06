#!/usr/bin/env bash
# ==============================================================================
# Kubernetes Node Reset & Teardown (kubeadm reset)
# ==============================================================================
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/scripts/common.sh"

check_root

log_header "Resetting Node & Removing Kubernetes"

# 1. kubeadm reset
if command -v kubeadm >/dev/null 2>&1; then
    log_info "Executing kubeadm reset -f..."
    kubeadm reset -f --cri-socket="${CRI_SOCKET:-unix:///run/containerd/containerd.sock}" || true
fi

# 2. Stop kubelet
log_info "Stopping kubelet..."
systemctl stop kubelet 2>/dev/null || true
systemctl disable kubelet 2>/dev/null || true

# 3. Clean virtual network interfaces
log_info "Removing virtual network devices..."
for iface in cni0 flannel.1 kube-ipvs0 tunl0 cilium_net cilium_host cali* vxlan.calico; do
    if ip link show "${iface}" >/dev/null 2>&1; then
        ip link set "${iface}" down 2>/dev/null || true
        ip link delete "${iface}" 2>/dev/null || true
    fi
done

# 4. Remove directories
log_info "Removing Kubernetes and CNI directories..."
rm -rf /etc/kubernetes \
       /var/lib/kubelet \
       /var/lib/etcd \
       /etc/cni/net.d \
       /var/lib/cni \
       /run/flannel \
       "${HOME}/.kube" \
       /root/.kube

# 5. Flush iptables if requested
if [[ "${1:-}" == "--purge-iptables" ]]; then
    log_info "Flushing iptables filter and nat tables..."
    iptables -F || true
    iptables -X || true
    iptables -t nat -F || true
    iptables -t nat -X || true
fi

# 6. Restart containerd clean
log_info "Restarting containerd..."
systemctl restart containerd 2>/dev/null || true

log_success "Kubernetes state purged and node reset."
