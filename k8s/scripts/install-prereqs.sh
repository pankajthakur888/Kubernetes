#!/usr/bin/env bash
# ==============================================================================
# Kubernetes Host Prerequisites (Swap, Kernel, Sysctl, Packages, Firewall)
# ==============================================================================
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"

check_root
detect_os
detect_wsl
detect_node_ip
load_config "${ROLE:-}"

log_header "Preparing Host Environment for Kubernetes"

# 1. Disable swap (Required by Kubelet)
log_info "Disabling swap..."
swapoff -a || true
if [[ -f /etc/fstab ]]; then
    sed -i '/\sswap\s/ s/^/#/' /etc/fstab || true
fi

# 2. Kernel modules
log_info "Configuring kernel modules (overlay, br_netfilter)..."
mkdir -p /etc/modules-load.d
cat >/etc/modules-load.d/k8s.conf <<EOF
overlay
br_netfilter
EOF

modprobe overlay || true
modprobe br_netfilter || true

# 3. Sysctl parameters
log_info "Applying Kubernetes sysctl network tuning..."
mkdir -p /etc/sysctl.d
cat >/etc/sysctl.d/99-kubernetes.conf <<EOF
net.bridge.bridge-nf-call-iptables=1
net.bridge.bridge-nf-call-ip6tables=1
net.ipv4.ip_forward=1
EOF

sysctl --system >/dev/null 2>&1 || true

# 4. Install OS dependencies
log_info "Installing system dependencies..."
case "${OS_FAMILY}" in
    debian)
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -y
        apt-get install -y \
            curl \
            wget \
            ca-certificates \
            apt-transport-https \
            gnupg \
            lsb-release \
            socat \
            conntrack \
            ipset \
            ebtables \
            ethtool \
            openssl \
            jq \
            tar
        ;;
    rhel|amazon)
        PKG_MGR="dnf"
        command -v dnf >/dev/null 2>&1 || PKG_MGR="yum"
        ${PKG_MGR} install -y \
            curl \
            wget \
            ca-certificates \
            socat \
            conntrack-tools \
            ipset \
            ebtables \
            ethtool \
            openssl \
            jq \
            tar
        ;;
    generic)
        command -v curl >/dev/null 2>&1 || log_error "curl is required."
        ;;
esac

# 5. Configure firewall rules
log_info "Checking firewall configuration..."
if command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld; then
    log_info "Opening Kubernetes ports in firewalld..."
    # Control plane & Worker common ports
    firewall-cmd --permanent --add-port=6443/tcp || true      # Kubernetes API
    firewall-cmd --permanent --add-port=2379-2380/tcp || true # etcd server client API
    firewall-cmd --permanent --add-port=10250/tcp || true     # Kubelet API
    firewall-cmd --permanent --add-port=10257/tcp || true     # kube-controller-manager
    firewall-cmd --permanent --add-port=10259/tcp || true     # kube-scheduler
    firewall-cmd --permanent --add-port=8472/udp || true      # Flannel / VXLAN
    firewall-cmd --permanent --add-port=4789/udp || true      # Calico VXLAN
    firewall-cmd --permanent --add-port=30000-32767/tcp || true # NodePort Services
    firewall-cmd --reload || true
elif command -v ufw >/dev/null 2>&1 && ufw status | grep -q active; then
    log_info "Opening Kubernetes ports in UFW..."
    ufw allow 6443/tcp || true
    ufw allow 2379:2380/tcp || true
    ufw allow 10250/tcp || true
    ufw allow 10257/tcp || true
    ufw allow 10259/tcp || true
    ufw allow 8472/udp || true
    ufw allow 4789/udp || true
    ufw allow 30000:32767/tcp || true
fi

log_success "Host prerequisites configured successfully."
