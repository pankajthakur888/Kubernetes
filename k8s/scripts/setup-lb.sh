#!/usr/bin/env bash
# ==============================================================================
# HAProxy Control Plane API Load Balancer Setup for Kubernetes
# ==============================================================================
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"

check_root
detect_os
load_config

log_header "Kubernetes Control Plane HA API Load Balancer (HAProxy)"

CP1_IP="${1:-10.10.10.11}"
CP2_IP="${2:-10.10.10.12}"
CP3_IP="${3:-10.10.10.13}"

log_info "Configuring HAProxy backend servers on port 6443:"
echo "  CP1: ${CP1_IP}:6443"
echo "  CP2: ${CP2_IP}:6443"
echo "  CP3: ${CP3_IP}:6443"

if ! command -v haproxy >/dev/null 2>&1; then
    log_info "Installing HAProxy..."
    case "${OS_FAMILY}" in
        debian)
            apt-get update -y && apt-get install -y haproxy
            ;;
        rhel|amazon)
            dnf install -y haproxy || yum install -y haproxy
            ;;
        *)
            log_error "Please install haproxy package manually."
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

frontend k8s-apiserver
    bind *:6443
    mode tcp
    default_backend k8s-controlplane-backend

backend k8s-controlplane-backend
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

systemctl enable haproxy || true
systemctl restart haproxy || true

log_success "HAProxy configured and running on port 6443 (Dashboard: http://<LB_IP>:8404)"
