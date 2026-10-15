#!/usr/bin/env bash
# ==============================================================================
# Kubernetes Cluster-Wide Certificate Expiration Auditor
# Supports: Upstream Kubernetes (kubeadm), K3s, Kubeconfigs, and cert-manager
# ==============================================================================
set -Eeuo pipefail

BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

header() {
    echo -e "\n${BOLD}${CYAN}=== $1 ===${NC}"
}

check_file_expiry() {
    local cert_file="$1"
    local desc="$2"
    
    if [[ ! -f "${cert_file}" ]]; then
        return
    fi
    
    # Extract expiration date
    local end_date
    end_date=$(openssl x509 -enddate -noout -in "${cert_file}" 2>/dev/null | cut -d= -f2 || true)
    if [[ -z "${end_date}" ]]; then
        return
    fi
    
    local end_epoch
    end_epoch=$(date -d "${end_date}" +%s 2>/dev/null || date -j -f "%b %d %T %Y %Z" "${end_date}" +%s 2>/dev/null || true)
    local now_epoch
    now_epoch=$(date +%s)
    local diff_days=$(( (end_epoch - now_epoch) / 86400 ))
    
    if (( diff_days < 0 )); then
        echo -e "  [${RED}EXPIRED${NC}] ${desc} (${cert_file}) expired ${diff_days#-} days ago on ${end_date}"
    elif (( diff_days < 30 )); then
        echo -e "  [${YELLOW}EXPIRING SOON${NC}] ${desc} (${cert_file}) expires in ${diff_days} days on ${end_date}"
    else
        echo -e "  [${GREEN}VALID${NC}] ${desc} (${cert_file}): ${diff_days} days remaining (Expires: ${end_date})"
    fi
}

check_kubeconfig_expiry() {
    local conf_file="$1"
    local desc="$2"
    
    if [[ ! -f "${conf_file}" ]]; then
        return
    fi
    
    local cert_b64
    cert_b64=$(grep "client-certificate-data:" "${conf_file}" 2>/dev/null | awk '{print $2}' || true)
    if [[ -z "${cert_b64}" ]]; then
        return
    fi
    
    local end_date
    end_date=$(echo "${cert_b64}" | base64 -d 2>/dev/null | openssl x509 -enddate -noout 2>/dev/null | cut -d= -f2 || true)
    if [[ -z "${end_date}" ]]; then
        return
    fi
    
    local end_epoch
    end_epoch=$(date -d "${end_date}" +%s 2>/dev/null || date -j -f "%b %d %T %Y %Z" "${end_date}" +%s 2>/dev/null || true)
    local now_epoch
    now_epoch=$(date +%s)
    local diff_days=$(( (end_epoch - now_epoch) / 86400 ))
    
    if (( diff_days < 0 )); then
        echo -e "  [${RED}EXPIRED${NC}] ${desc} (${conf_file}) client cert expired ${diff_days#-} days ago on ${end_date}"
    elif (( diff_days < 30 )); then
        echo -e "  [${YELLOW}EXPIRING SOON${NC}] ${desc} (${conf_file}) client cert expires in ${diff_days} days on ${end_date}"
    else
        echo -e "  [${GREEN}VALID${NC}] ${desc} (${conf_file}): ${diff_days} days remaining (Expires: ${end_date})"
    fi
}

echo -e "${BOLD}====================================================================${NC}"
echo -e "${BOLD}          Kubernetes Cluster Certificate Expiration Audit          ${NC}"
echo -e "${BOLD}====================================================================${NC}"

# 1. Upstream Kubernetes (kubeadm) Certificates
if [[ -d "/etc/kubernetes/pki" ]]; then
    header "Upstream Kubernetes Control-Plane PKI (/etc/kubernetes/pki)"
    if command -v kubeadm >/dev/null 2>&1; then
        kubeadm certs check-expiration || true
    else
        for crt in /etc/kubernetes/pki/*.crt /etc/kubernetes/pki/etcd/*.crt; do
            [[ -f "${crt}" ]] && check_file_expiry "${crt}" "$(basename "${crt}")"
        done
    fi
fi

# 2. Control Plane Kubeconfigs
if [[ -d "/etc/kubernetes" ]]; then
    header "Cluster Administrative Kubeconfigs (/etc/kubernetes/*.conf)"
    check_kubeconfig_expiry "/etc/kubernetes/admin.conf" "admin.conf"
    check_kubeconfig_expiry "/etc/kubernetes/kubelet.conf" "kubelet.conf"
    check_kubeconfig_expiry "/etc/kubernetes/controller-manager.conf" "controller-manager.conf"
    check_kubeconfig_expiry "/etc/kubernetes/scheduler.conf" "scheduler.conf"
fi

# 3. K3s Cluster Certificates
if [[ -d "/var/lib/rancher/k3s/server/tls" ]]; then
    header "K3s Cluster PKI Certificates (/var/lib/rancher/k3s/server/tls)"
    if command -v k3s >/dev/null 2>&1; then
        k3s certificate check || true
    fi
    for crt in /var/lib/rancher/k3s/server/tls/*.crt; do
        [[ -f "${crt}" ]] && check_file_expiry "${crt}" "$(basename "${crt}")"
    done
fi

# 4. Kubelet Client Certificates
if [[ -d "/var/lib/kubelet/pki" ]]; then
    header "Kubelet Node Certificates (/var/lib/kubelet/pki)"
    for crt in /var/lib/kubelet/pki/*.crt /var/lib/kubelet/pki/*.pem; do
        [[ -f "${crt}" ]] && check_file_expiry "${crt}" "$(basename "${crt}")"
    done
fi

# 5. cert-manager Application Certificates
KUBECTL="kubectl"
if ! command -v kubectl >/dev/null 2>&1 && command -v k3s >/dev/null 2>&1; then
    KUBECTL="k3s kubectl"
fi

if command -v "${KUBECTL}" >/dev/null 2>&1; then
    if ${KUBECTL} get crd certificates.cert-manager.io >/dev/null 2>&1; then
        header "cert-manager Application TLS Certificates"
        ${KUBECTL} get certificates -A -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,READY:.status.conditions[0].status,SECRET:.spec.secretName,EXPIRATION:.status.notAfter || true
    fi
fi

echo -e "\n${BOLD}====================================================================${NC}"
echo -e "${GREEN}${BOLD}Certificate audit completed successfully.${NC}"
echo -e "${BOLD}====================================================================${NC}"
