#!/usr/bin/env bash
# ==============================================================================
# K3s Cluster Uninstaller & Node Cleanup
# ==============================================================================
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/scripts/common.sh"

check_root

log_header "Uninstalling K3s and Purging Cluster Data"

# 1. Run official uninstall scripts if present
if [[ -f /usr/local/bin/k3s-uninstall.sh ]]; then
    log_info "Executing /usr/local/bin/k3s-uninstall.sh..."
    /usr/local/bin/k3s-uninstall.sh || true
fi

if [[ -f /usr/local/bin/k3s-agent-uninstall.sh ]]; then
    log_info "Executing /usr/local/bin/k3s-agent-uninstall.sh..."
    /usr/local/bin/k3s-agent-uninstall.sh || true
fi

# 2. Stop any remaining systemd units
log_info "Stopping any leftover services..."
systemctl stop k3s 2>/dev/null || true
systemctl stop k3s-agent 2>/dev/null || true
systemctl disable k3s 2>/dev/null || true
systemctl disable k3s-agent 2>/dev/null || true

# 3. Clean network links
log_info "Removing virtual networking interfaces (cni0, flannel.1, calico, cilium)..."
for iface in cni0 flannel.1 kube-ipvs0 tunl0 cilium_net cilium_host; do
    if ip link show "${iface}" >/dev/null 2>&1; then
        ip link set "${iface}" down 2>/dev/null || true
        ip link delete "${iface}" 2>/dev/null || true
    fi
done

# 4. Remove leftover data directories
log_info "Cleaning data directories..."
for mount_pt in /var/lib/kubelet /var/lib/rancher/k3s; do
    if grep -q " ${mount_pt}" /proc/mounts 2>/dev/null; then
        umount -l "${mount_pt}" 2>/dev/null || true
    fi
done
rm -rf /etc/rancher/k3s \
       /var/lib/rancher/k3s \
       /var/lib/kubelet \
       /run/k3s \
       /run/flannel \
       /var/lib/cni \
       /etc/cni/net.d \
       /etc/modules-load.d/k3s.conf \
       /etc/sysctl.d/90-k3s.conf || true

# 5. Flush iptables if requested
if [[ "${1:-}" == "--purge-iptables" ]]; then
    log_info "Flushing iptables filter and nat chains..."
    iptables -F || true
    iptables -X || true
    iptables -t nat -F || true
    iptables -t nat -X || true
fi

log_success "K3s uninstalled and host cleaned."
