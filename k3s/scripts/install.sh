#!/usr/bin/env bash
# ==============================================================================
# System Prerequisites & Host Preparation
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

log_header "Preparing Host Environment for K3s"

# 1. Disable swap
log_info "Disabling swap..."
swapoff -a || true
if [[ -f /etc/fstab ]]; then
    sed -i '/\sswap\s/ s/^/#/' /etc/fstab || true
fi

# 2. Configure kernel modules
log_info "Configuring kernel modules (overlay, br_netfilter)..."
mkdir -p /etc/modules-load.d
cat >/etc/modules-load.d/k3s.conf <<EOF
overlay
br_netfilter
EOF

modprobe overlay || true
modprobe br_netfilter || true

# 3. Configure sysctl network settings
log_info "Applying network sysctl tuning..."
mkdir -p /etc/sysctl.d
cat >/etc/sysctl.d/90-k3s.conf <<EOF
net.bridge.bridge-nf-call-iptables=1
net.bridge.bridge-nf-call-ip6tables=1
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1
EOF

sysctl --system >/dev/null 2>&1 || true

# 4. Install OS-specific dependencies
log_info "Installing system dependencies..."
case "${OS_FAMILY}" in
    debian)
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -y
        apt-get install -y \
            curl \
            wget \
            ca-certificates \
            iptables \
            socat \
            conntrack \
            ipset \
            ethtool \
            bash \
            openssl \
            jq \
            tar
        ;;
    rhel)
        PKG_MGR="dnf"
        command -v dnf >/dev/null 2>&1 || PKG_MGR="yum"
        ${PKG_MGR} install -y \
            curl \
            wget \
            ca-certificates \
            iptables \
            socat \
            conntrack \
            ipset \
            ethtool \
            bash \
            openssl \
            jq \
            tar
        
        # Check SELinux on RHEL
        if command -v getenforce >/dev/null 2>&1; then
            SELINUX_STATUS=$(getenforce)
            log_info "SELinux status: ${SELINUX_STATUS}"
            if [[ "${SELINUX_STATUS}" == "Enforcing" ]]; then
                log_info "Configuring K3s SELinux policy repository..."
                cat >/etc/yum.repos.d/rancher-k3s-common.repo <<EOF
[rancher-k3s-common]
name=Rancher K3s Common
baseurl=https://rpm.rancher.io/k3s/latest/common/centos/7/noarch
enabled=1
gpgcheck=1
gpgkey=https://rpm.rancher.io/public.key
EOF
                ${PKG_MGR} install -y k3s-selinux || log_warn "Could not install k3s-selinux automatically. Ensure policy allows container sockets."
            fi
        fi
        ;;
    generic)
        command -v curl >/dev/null 2>&1 || log_error "curl is required."
        command -v iptables >/dev/null 2>&1 || log_warn "iptables not found. Verify network forwarding."
        ;;
esac

# 5. Firewall configuration
log_info "Checking firewall configuration..."
if command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld; then
    log_info "Opening K3s ports in firewalld..."
    firewall-cmd --permanent --add-port=6443/tcp || true      # K3s API server
    firewall-cmd --permanent --add-port=10250/tcp || true     # Kubelet metrics
    firewall-cmd --permanent --add-port=8472/udp || true      # Flannel VXLAN
    firewall-cmd --permanent --add-port=2379-2380/tcp || true # etcd peer
    firewall-cmd --permanent --add-port=51820-51821/udp || true # Wireguard
    firewall-cmd --reload || true
elif command -v ufw >/dev/null 2>&1 && ufw status | grep -q active; then
    log_info "Opening K3s ports in UFW..."
    ufw allow 6443/tcp || true
    ufw allow 10250/tcp || true
    ufw allow 8472/udp || true
    ufw allow 2379:2380/tcp || true
fi

log_success "Host preparation completed successfully."
