#!/usr/bin/env bash
# ==============================================================================
# MetalLB Bare-Metal Load Balancer Installer for Kubernetes
# ==============================================================================
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"

check_root
load_config

METALLB_VERSION="v0.14.8"
IP_POOL="${1:-}"

export KUBECONFIG="${KUBECONFIG:-/etc/kubernetes/admin.conf}"

log_header "Installing MetalLB Load Balancer (${METALLB_VERSION})"

if [[ -z "${IP_POOL}" ]]; then
    detect_node_ip
    IP_PREFIX=$(echo "${NODE_IP}" | awk -F. '{print $1"."$2"."$3}')
    IP_POOL="${IP_PREFIX}.220-${IP_PREFIX}.240"
    log_warn "No IP range provided. Using detected subnet pool: ${IP_POOL}"
fi

log_info "Enabling strictARP in kube-proxy (Required by MetalLB)..."
kubectl get configmap kube-proxy -n kube-system -o yaml | \
    sed -e "s/strictARP: false/strictARP: true/" | \
    kubectl apply -f - -n kube-system || true

log_info "Applying MetalLB native manifests..."
kubectl apply -f "https://raw.githubusercontent.com/metallb/metallb/${METALLB_VERSION}/config/manifests/metallb-native.yaml"

log_info "Waiting for MetalLB controller deployment to be ready..."
kubectl rollout status deployment/controller -n metallb-system --timeout=180s
kubectl rollout status daemonset/speaker -n metallb-system --timeout=180s

log_info "Configuring IPAddressPool and L2Advertisement with pool: ${IP_POOL}..."
cat <<EOF | kubectl apply -f -
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

log_success "MetalLB configured with IP pool: ${IP_POOL}"
