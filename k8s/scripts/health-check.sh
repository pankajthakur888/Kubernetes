#!/usr/bin/env bash
# ==============================================================================
# Kubernetes Cluster Diagnostics & Health Audit
# ==============================================================================
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"

load_config

log_header "Kubernetes Cluster Health & Diagnostics"

# 1. Systemd services
log_info "Checking local system services..."
for svc in containerd kubelet; do
    if systemctl is-active --quiet "${svc}" 2>/dev/null; then
        echo -e "  [x] ${svc}: ${GREEN}Active (Running)${NC}"
    else
        echo -e "  [ ] ${svc}: ${YELLOW}Inactive or stopped${NC}"
    fi
done

# 2. Static pod manifests
log_info "Inspecting local control-plane manifests in /etc/kubernetes/manifests..."
if [[ -d /etc/kubernetes/manifests ]]; then
    for manifest in kube-apiserver kube-controller-manager kube-scheduler etcd; do
        if [[ -f "/etc/kubernetes/manifests/${manifest}.yaml" ]]; then
            echo -e "  [x] Manifest found: ${manifest}.yaml"
        fi
    done
fi

# 3. Kubectl cluster inspections
if command -v kubectl >/dev/null 2>&1; then
    KUBECONFIG_PATH="${KUBECONFIG:-/etc/kubernetes/admin.conf}"
    if [[ -f "${KUBECONFIG_PATH}" ]]; then
        export KUBECONFIG="${KUBECONFIG_PATH}"
        
        echo -e "\n${BOLD}Cluster Nodes:${NC}"
        kubectl get nodes -o wide || true

        echo -e "\n${BOLD}System Pods (kube-system):${NC}"
        kubectl get pods -n kube-system -o wide || true

        # Check for abnormal pods
        ABNORMAL_PODS=$(kubectl get pods -A --no-headers 2>/dev/null | grep -E 'CrashLoopBackOff|Error|Pending|OOMKilled' || true)
        if [[ -n "${ABNORMAL_PODS}" ]]; then
            echo -e "\n${YELLOW}[!] Warning: Pods in non-running states:${NC}"
            echo "${ABNORMAL_PODS}"
        else
            log_success "No failing pods detected across cluster namespaces."
        fi

        # CoreDNS status
        echo -e "\n${BOLD}CoreDNS Pods:${NC}"
        kubectl get pods -n kube-system -l k8s-app=kube-dns || true
    fi
fi

log_success "Diagnostic check completed."
