#!/usr/bin/env bash
# ==============================================================================
# K3s Cluster Certificate Rotation Automation
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

if ! command -v k3s >/dev/null 2>&1; then
    log_error "'k3s' command not found."
fi

echo -e "${BOLD}====================================================================${NC}"
echo -e "${BOLD}               K3s Component Certificate Rotation                   ${NC}"
echo -e "${BOLD}====================================================================${NC}"

# Step 1: Check current certificates
log_info "Auditing current K3s certificates on disk..."
k3s certificate check || true

# Step 2: Stop K3s service
log_info "Stopping k3s service..."
systemctl stop k3s

# Step 3: Rotate component certificates
log_info "Executing 'k3s certificate rotate'..."
k3s certificate rotate

# Step 4: Restart K3s service
log_info "Starting k3s service..."
systemctl start k3s

# Step 5: Wait for API server ready
log_info "Waiting for K3s API server to become ready..."
ATTEMPTS=0
MAX_ATTEMPTS=20
until k3s kubectl get nodes >/dev/null 2>&1 || [[ ${ATTEMPTS} -ge ${MAX_ATTEMPTS} ]]; do
    sleep 2
    ATTEMPTS=$((ATTEMPTS + 1))
done

# Step 6: Verify new expiration
echo
log_info "Updated K3s certificates status:"
k3s certificate check || true

log_success "K3s component certificates rotated successfully!"
