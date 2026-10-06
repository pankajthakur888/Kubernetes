#!/usr/bin/env bash
# ==============================================================================
# CSI Storage Driver Installer (Local-Path / Cloud CSI)
# ==============================================================================
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"

check_root
load_config

export KUBECONFIG="${KUBECONFIG:-/etc/kubernetes/admin.conf}"

log_header "Installing CSI Storage Driver (${ENVIRONMENT:-onprem})"

case "${ENVIRONMENT:-onprem}" in
    onprem)
        log_info "Deploying Rancher Local-Path Provisioner CSI..."
        kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.30/deploy/local-path-storage.yaml
        log_info "Setting local-path as default storage class..."
        kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}' || true
        log_success "Local-Path CSI deployed and set as default StorageClass."
        ;;
    aws)
        log_info "For AWS, install the AWS EBS CSI Driver via Helm or AWS IAM OIDC:"
        echo "  helm repo add aws-ebs-csi-driver https://kubernetes-sigs.github.io/aws-ebs-csi-driver"
        echo "  helm install aws-ebs-csi-driver aws-ebs-csi-driver/aws-ebs-csi-driver -n kube-system"
        ;;
    gcp)
        log_info "For GCP, deploy the Google Compute Engine Persistent Disk CSI Driver."
        ;;
    azure)
        log_info "For Azure, deploy the Azure Disk and Azure File CSI Drivers."
        ;;
esac
