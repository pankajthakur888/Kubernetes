#!/usr/bin/env bash
# ==============================================================================
# MetalLB Bare-Metal Load Balancer Installer
# ==============================================================================
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"

check_root
load_config

METALLB_VERSION="v0.14.8"
IP_POOL="${1:-${METALLB_IP_RANGE:-}}"

log_header "Installing MetalLB Load Balancer (${METALLB_VERSION})"

if [[ -z "${IP_POOL}" ]]; then
    # Default sample pool based on node IP prefix
    detect_node_ip
    IP_PREFIX=$(echo "${NODE_IP}" | awk -F. '{print $1"."$2"."$3}')
    IP_POOL="${IP_PREFIX}.200-${IP_PREFIX}.220"
    log_warn "No IP range specified. Using detected subnet pool: ${IP_POOL}"
fi

log_info "Applying MetalLB native manifests..."
k3s kubectl apply -f "https://raw.githubusercontent.com/metallb/metallb/${METALLB_VERSION}/config/manifests/metallb-native.yaml"

log_info "Waiting for MetalLB controller deployment to be ready..."
k3s kubectl rollout status deployment/controller -n metallb-system --timeout=180s
k3s kubectl rollout status daemonset/speaker -n metallb-system --timeout=180s

log_info "Configuring IPAddressPool and L2Advertisement with pool: ${IP_POOL}..."
cat <<EOF | k3s kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default-pool
  namespace: metallb-system
spec:
  addresses:
  - ${IP_POOL}
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: default-l2-adv
  namespace: metallb-system
spec:
  ipAddressPools:
  - default-pool
EOF

log_success "MetalLB installed and configured with IP Pool: ${IP_POOL}"
