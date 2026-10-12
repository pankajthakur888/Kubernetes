#!/usr/bin/env bash
# ==============================================================================
# Automated Knative Serving & Kourier Ingress Installer
# Works on Kubernetes (kubeadm) and K3s (WSL2 / Linux)
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

# Determine kubectl command
KUBECTL="kubectl"
if ! command -v kubectl >/dev/null 2>&1; then
    if command -v k3s >/dev/null 2>&1; then
        KUBECTL="k3s kubectl"
    else
        log_error "Neither 'kubectl' nor 'k3s' was found. Please ensure cluster is running."
    fi
fi

KNATIVE_VERSION="v1.15.0"

log_info "Installing Knative Serving CRDs (${KNATIVE_VERSION})..."
${KUBECTL} apply -f "https://github.com/knative/serving/releases/download/knative-${KNATIVE_VERSION}/serving-crds.yaml"

log_info "Installing Knative Serving Core components..."
${KUBECTL} apply -f "https://github.com/knative/serving/releases/download/knative-${KNATIVE_VERSION}/serving-core.yaml"

log_info "Installing Kourier lightweight networking layer..."
${KUBECTL} apply -f "https://github.com/knative/net-kourier/releases/download/knative-${KNATIVE_VERSION}/kourier.yaml"

log_info "Configuring Knative Serving to use Kourier as default ingress..."
${KUBECTL} patch configmap/config-network \
  --namespace knative-serving \
  --type merge \
  --patch '{"data":{"ingress-class":"kourier.ingress.networking.knative.dev"}}'

log_info "Configuring default Magic DNS (sslip.io)..."
${KUBECTL} apply -f "https://github.com/knative/serving/releases/download/knative-${KNATIVE_VERSION}/serving-default-domain.yaml" 2>/dev/null || true

log_info "Waiting for Knative Serving control-plane pods to become ready..."
${KUBECTL} wait --namespace knative-serving \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/part-of=knative-serving \
  --timeout=120s 2>/dev/null || log_warn "Pods are still initializing. Check with: ${KUBECTL} get pods -n knative-serving"

log_success "Knative Serving installation completed successfully!"
echo -e "
${BOLD}Next Steps:${NC}
  1. Deploy a serverless service:
     ${KUBECTL} apply -f manifests/01-hello-service.yaml
  2. Verify service URL and status:
     ${KUBECTL} get ksvc
"
