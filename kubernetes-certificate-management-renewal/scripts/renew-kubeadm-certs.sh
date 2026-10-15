#!/usr/bin/env bash
# ==============================================================================
# Upstream Kubernetes (kubeadm) Certificate Renewal Automation
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

if [[ "${EUID}" -ne 0 ]]; then
    log_error "This script must be run as root (sudo)."
fi

if ! command -v kubeadm >/dev/null 2>&1; then
    log_error "'kubeadm' command not found. This script is intended for upstream kubeadm clusters."
fi

PKI_DIR="/etc/kubernetes/pki"
if [[ ! -d "${PKI_DIR}" ]]; then
    log_error "Directory ${PKI_DIR} does not exist. Ensure this node is a Kubernetes control plane."
fi

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="/etc/kubernetes/backup-pki-${TIMESTAMP}"

echo -e "${BOLD}====================================================================${NC}"
echo -e "${BOLD}         Kubernetes Control Plane Certificate Renewal (kubeadm)     ${NC}"
echo -e "${BOLD}====================================================================${NC}"

# Step 1: Backup PKI and Kubeconfig files
log_info "Creating backup of PKI certificates in ${BACKUP_DIR}..."
mkdir -p "${BACKUP_DIR}"
cp -r "${PKI_DIR}" "${BACKUP_DIR}/pki"
cp -f /etc/kubernetes/*.conf "${BACKUP_DIR}/" 2>/dev/null || true
log_success "Backup completed."

# Step 2: Display current expiration before renewal
log_info "Current certificate status:"
kubeadm certs check-expiration || true

# Step 3: Renew all control plane certificates
log_info "Executing 'kubeadm certs renew all'..."
kubeadm certs renew all

# Step 4: Update administrative kubeconfig
log_info "Updating administrative kubeconfig files..."
if [[ -f "/etc/kubernetes/admin.conf" ]]; then
    mkdir -p "${HOME}/.kube"
    cp -f /etc/kubernetes/admin.conf "${HOME}/.kube/config"
    
    if [[ -n "${SUDO_USER:-}" ]]; then
        USER_HOME=$(getent passwd "${SUDO_USER}" | cut -d: -f6)
        mkdir -p "${USER_HOME}/.kube"
        cp -f /etc/kubernetes/admin.conf "${USER_HOME}/.kube/config"
        chown -R "${SUDO_USER}:${SUDO_USER}" "${USER_HOME}/.kube"
    fi
    log_success "Kubeconfig files updated with renewed certificates."
fi

# Step 5: Restart static pods to reload in-memory certificates
log_info "Restarting control plane static pods to reload certificates into memory..."
if [[ -d "/etc/kubernetes/manifests" ]]; then
    TMP_MANIFESTS="/tmp/k8s-manifests-restart-${TIMESTAMP}"
    mkdir -p "${TMP_MANIFESTS}"
    mv /etc/kubernetes/manifests/*.yaml "${TMP_MANIFESTS}/"
    log_info "Waiting 10s for Kubelet to terminate old control plane pods..."
    sleep 10
    mv "${TMP_MANIFESTS}"/*.yaml /etc/kubernetes/manifests/
    rm -rf "${TMP_MANIFESTS}"
    log_success "Static pod manifests restored. Kubelet is spinning up renewed pods."
fi

# Restart Kubelet
log_info "Restarting kubelet service..."
systemctl daemon-reload
systemctl restart kubelet || true

# Step 6: Verify new expiration
echo
log_info "New certificate expiration status:"
kubeadm certs check-expiration || true

log_success "Kubernetes certificates renewed successfully!"
