#!/usr/bin/env bash
# ==============================================================================
# Ingress Controller Installer (Ingress-NGINX / Traefik)
# ==============================================================================
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"

check_root
load_config

INGRESS_TYPE="${1:-nginx}"

log_header "Configuring Ingress Controller: ${INGRESS_TYPE}"

case "${INGRESS_TYPE}" in
    nginx|ingress-nginx)
        log_info "Deploying Ingress-NGINX Controller..."
        k3s kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/baremetal/deploy.yaml
        log_info "Waiting for ingress-nginx controller deployment..."
        k3s kubectl rollout status deployment/ingress-nginx-controller -n ingress-nginx --timeout=180s || true
        log_success "Ingress-NGINX deployed successfully."
        ;;
    traefik)
        log_info "Traefik is enabled by default in K3s unless --disable=traefik is specified."
        k3s kubectl get pods -n kube-system -l app.kubernetes.io/name=traefik
        ;;
    *)
        log_error "Unsupported ingress controller: ${INGRESS_TYPE}. Choose 'nginx' or 'traefik'."
        ;;
esac
