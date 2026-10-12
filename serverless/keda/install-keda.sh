#!/usr/bin/env bash
# ==============================================================================
# Automated KEDA (Kubernetes Event-driven Autoscaling) Installer
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

KEDA_VERSION="2.15.1"

# Check if Helm is available
if command -v helm >/dev/null 2>&1; then
    log_info "Installing KEDA via Helm (${KEDA_VERSION})..."
    helm repo add kedacore https://kedacore.github.io/charts 2>/dev/null || true
    helm repo update kedacore
    helm upgrade --install keda kedacore/keda \
      --namespace keda \
      --create-namespace \
      --version "${KEDA_VERSION}" \
      --wait
else
    log_info "Helm not found. Installing KEDA using official release YAML (${KEDA_VERSION})..."
    ${KUBECTL} apply --server-side -f "https://github.com/kedacore/keda/releases/download/v${KEDA_VERSION}/keda-${KEDA_VERSION}.yaml"
fi

log_info "Waiting for KEDA Operator and Metrics Server pods to become ready..."
${KUBECTL} wait --namespace keda \
  --for=condition=ready pod \
  --selector=app=keda-operator \
  --timeout=120s 2>/dev/null || log_warn "KEDA pods are still initializing. Check with: ${KUBECTL} get pods -n keda"

log_success "KEDA Operator installed successfully!"
echo -e "
${BOLD}Next Steps:${NC}
  1. Inspect KEDA Custom Resource Definitions:
     ${KUBECTL} get crd | grep keda
  2. Deploy a ScaledObject:
     ${KUBECTL} apply -f manifests/01-scaledobject-cron.yaml
  3. Inspect ScaledObjects & active HPAs:
     ${KUBECTL} get scaledobject
     ${KUBECTL} get hpa
"
