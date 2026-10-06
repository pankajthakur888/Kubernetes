#!/usr/bin/env bash
# ==============================================================================
# HAProxy Control Plane API Load Balancer Setup
# ==============================================================================
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"

check_root
detect_os
load_config

log_header "Control Plane HA API Load Balancer Setup (HAProxy)"

CP1_IP="${1:-10.10.10.10}"
CP2_IP="${2:-10.10.10.11}"
CP3_IP="${3:-10.10.10.12}"

log_info "Configuring HAProxy for Control Planes:"
echo "  CP1: ${CP1_IP}:6443"
echo "  CP2: ${CP2_IP}:6443"
echo "  CP3: ${CP3_IP}:6443"

# Install HAProxy if not present
if ! command -v haproxy >/dev/null 2>&1; then
    log_info "Installing HAProxy..."
    case "${OS_FAMILY}" in
        debian)
            apt-get update -y && apt-get install -y haproxy
            ;;
        rhel)
            dnf install -y haproxy || yum install -y haproxy
            ;;
        *)
            log_error "Install haproxy package manually on this system."
            ;;
    esac
fi

cat >/etc/haproxy/haproxy.cfg <<EOF
global
    log /dev/log local0
    log /dev/log local1 notice
    chroot /var/lib/haproxy
    user haproxy
    group haproxy
    daemon

defaults
    log     global
    mode    tcp
    option  tcplog
    option  dontlognull
    timeout connect 5000ms
    timeout client  50000ms
    timeout server  50000ms

frontend k3s-apiserver
    bind *:6443
    mode tcp
    default_backend k3s-controlplane-backend

backend k3s-controlplane-backend
    mode tcp
    balance roundrobin
    option tcp-check
    server cp1 ${CP1_IP}:6443 check check-ssl verify none fall 3 rise 2
    server cp2 ${CP2_IP}:6443 check check-ssl verify none fall 3 rise 2
    server cp3 ${CP3_IP}:6443 check check-ssl verify none fall 3 rise 2

frontend stats
    bind *:8404
    mode http
    stats enable
    stats uri /
    stats refresh 10s
EOF

systemctl enable haproxy
systemctl restart haproxy

log_success "HAProxy configured and running on port 6443 (Stats dashboard on port 8404)"
