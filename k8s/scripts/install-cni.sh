#!/usr/bin/env bash
# ==============================================================================
# CNI Installation Manager for Kubernetes (Calico / Cilium)
# ==============================================================================
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"

check_root
load_config

CNI_TARGET="${1:-${CNI:-cilium}}"
export KUBECONFIG="${KUBECONFIG:-/etc/kubernetes/admin.conf}"

log_header "Installing CNI Plugin: ${CNI_TARGET}"

case "${CNI_TARGET}" in
    calico)
        log_info "Deploying Tigera Calico Operator..."
        kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.2/manifests/tigera-operator.yaml || true
        
        log_info "Applying Calico Custom Resources with CIDR ${POD_CIDR:-10.244.0.0/16}..."
        cat <<EOF | kubectl apply -f -
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  calicoNetwork:
    ipPools:
    - name: default-ipv4-ippool
      blockSize: 26
      cidr: ${POD_CIDR:-10.244.0.0/16}
      encapsulation: VXLAN
      natOutgoing: Enabled
      nodeSelector: all()
---
apiVersion: operator.tigera.io/v1
kind: APIServer
metadata:
  name: default
spec: {}
EOF
        log_info "Waiting for Calico daemonset in calico-system..."
        kubectl rollout status daemonset/calico-node -n calico-system --timeout=180s || true
        log_success "Calico CNI deployed successfully."
        ;;

    cilium)
        log_info "Installing Cilium CNI..."
        if ! command -v cilium >/dev/null 2>&1; then
            log_info "Downloading Cilium CLI..."
            CILIUM_CLI_VERSION=$(curl -s --connect-timeout 10 https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt 2>/dev/null || echo "v0.20.1")
            [[ -n "${CILIUM_CLI_VERSION}" ]] || CILIUM_CLI_VERSION="v0.20.1"
            CLI_ARCH="amd64"
            if [ "$(uname -m)" = "aarch64" ]; then CLI_ARCH="arm64"; fi
            curl -L --fail --remote-name-all "https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz"
            tar xzf "cilium-linux-${CLI_ARCH}.tar.gz" -C /usr/local/bin
            rm -f "cilium-linux-${CLI_ARCH}.tar.gz"
        fi
        cilium install --set ipam.operator.clusterPoolIPv4PodCIDRList="${POD_CIDR:-10.244.0.0/16}"
        cilium status --wait
        log_success "Cilium CNI deployed successfully."
        ;;

    *)
        log_error "Unsupported CNI '${CNI_TARGET}'. Choose 'calico' or 'cilium'."
        ;;
esac
