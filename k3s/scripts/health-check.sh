#!/usr/bin/env bash
# ==============================================================================
# Cluster Health Check and Diagnostics
# ==============================================================================
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"

load_config

log_header "K3s Cluster Health & Diagnostic Check"

# 1. Check local systemd services
log_info "Checking local system services..."
SERVER_ACTIVE=false
AGENT_ACTIVE=false

if systemctl is-active --quiet k3s 2>/dev/null; then
    SERVER_ACTIVE=true
    echo -e "  [x] k3s (server): ${GREEN}Active (Running)${NC}"
else
    echo -e "  [ ] k3s (server): Inactive"
fi

if systemctl is-active --quiet k3s-agent 2>/dev/null; then
    AGENT_ACTIVE=true
    echo -e "  [x] k3s-agent (worker): ${GREEN}Active (Running)${NC}"
else
    echo -e "  [ ] k3s-agent (worker): Inactive"
fi

if [[ "${SERVER_ACTIVE}" == "false" && "${AGENT_ACTIVE}" == "false" ]]; then
    log_warn "Neither k3s server nor agent is currently active on this host."
fi

# 2. Control plane specific checks
if [[ "${SERVER_ACTIVE}" == "true" ]]; then
    log_info "Verifying Control-Plane API & etcd health..."
    
    # API readyz check
    API_STATUS=$(curl -k -s -o /dev/null -w "%{http_code}" https://127.0.0.1:6443/readyz 2>/dev/null || echo "000")
    if [[ "${API_STATUS}" == "200" ]]; then
        echo -e "  [x] API Server Ready (/readyz): ${GREEN}HTTP 200 OK${NC}"
    else
        echo -e "  [!] API Server Ready (/readyz): ${RED}HTTP ${API_STATUS}${NC}"
    fi

    # etcd snapshots check
    if command -v k3s >/dev/null 2>&1; then
        echo -e "\n${BOLD}etcd Snapshot Status:${NC}"
        k3s etcd-snapshot list 2>/dev/null || log_warn "Could not retrieve etcd snapshots"
    fi

    # Node status check
    echo -e "\n${BOLD}Cluster Nodes:${NC}"
    k3s kubectl get nodes -o wide || log_warn "kubectl get nodes failed"

    # NotReady nodes check
    NOT_READY=$(k3s kubectl get nodes --no-headers 2>/dev/null | grep -v ' Ready ' || true)
    if [[ -n "${NOT_READY}" ]]; then
        log_warn "Detected NotReady nodes:\n${NOT_READY}"
    else
        log_success "All cluster nodes report Ready."
    fi

    # System Pods check
    echo -e "\n${BOLD}System Pods (kube-system):${NC}"
    k3s kubectl get pods -n kube-system -o wide || true

    # Abnormal pods check across all namespaces
    ABNORMAL_PODS=$(k3s kubectl get pods -A --no-headers 2>/dev/null | grep -E 'CrashLoopBackOff|Error|Pending|OOMKilled|ContainerCreating' || true)
    if [[ -n "${ABNORMAL_PODS}" ]]; then
        echo -e "\n${YELLOW}[!] Pods in abnormal states:${NC}"
        echo "${ABNORMAL_PODS}"
    else
        log_success "No failing pods detected across cluster namespaces."
    fi

    # CoreDNS verification
    echo -e "\n${BOLD}CoreDNS Status:${NC}"
    COREDNS_PODS=$(k3s kubectl get pods -n kube-system -l k8s-app=kube-dns --no-headers 2>/dev/null || true)
    echo "${COREDNS_PODS}"

fi

log_success "Health check completed."
