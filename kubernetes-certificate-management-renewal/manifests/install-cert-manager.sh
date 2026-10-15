#!/usr/bin/env bash
# ==============================================================================
# Automated cert-manager Installer
# ==============================================================================
set -Eeuo pipefail

BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${BOLD}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

KUBECTL="kubectl"
if ! command -v kubectl >/dev/null 2>&1 && command -v k3s >/dev/null 2>&1; then
    KUBECTL="k3s kubectl"
fi

CERT_MANAGER_VERSION="v1.15.3"

log_info "Installing cert-manager (${CERT_MANAGER_VERSION}) with native CRDs..."
${KUBECTL} apply -f "https://github.com/cert-manager/cert-manager/releases/download/${CERT_MANAGER_VERSION}/cert-manager.yaml"

log_info "Waiting for cert-manager controller, webhook, and cainjector pods to become ready..."
${KUBECTL} wait --namespace cert-manager \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/instance=cert-manager \
  --timeout=180s 2>/dev/null || log_warn "Pods are still initializing. Check with: ${KUBECTL} get pods -n cert-manager"

log_success "cert-manager installed successfully!"
echo -e "
${BOLD}Next Steps:${NC}
  1. Inspect cert-manager CRDs:
     ${KUBECTL} get crds | grep cert-manager
  2. Apply a ClusterIssuer:
     ${KUBECTL} apply -f manifests/01-clusterissuer-selfsigned.yaml
     ${KUBECTL} apply -f manifests/02-clusterissuer-letsencrypt.yaml
  3. Verify ClusterIssuers:
     ${KUBECTL} get clusterissuer
"
