#!/usr/bin/env bash
# ==============================================================================
# Kubernetes Official Community Packages (kubeadm, kubelet, kubectl)
# ==============================================================================
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"

check_root
detect_os
load_config

K8S_VER="${K8S_VERSION:-v1.31}"

log_header "Configuring Official Kubernetes Repository (${K8S_VER}) & Packages"

case "${OS_FAMILY}" in
    debian)
        export DEBIAN_FRONTEND=noninteractive
        mkdir -p /etc/apt/keyrings

        log_info "Fetching Kubernetes apt release key from pkgs.k8s.io..."
        curl -fsSL "https://pkgs.k8s.io/core:/stable:/${K8S_VER}/deb/Release.key" | \
            gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

        log_info "Writing /etc/apt/sources.list.d/kubernetes.list..."
        echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${K8S_VER}/deb/ /" > \
            /etc/apt/sources.list.d/kubernetes.list

        apt-get update -y
        log_info "Installing kubelet, kubeadm, kubectl..."
        apt-get install -y kubelet kubeadm kubectl

        log_info "Holding packages at version ${K8S_VER}..."
        apt-mark hold kubelet kubeadm kubectl || true
        ;;

    rhel|amazon)
        PKG_MGR="dnf"
        command -v dnf >/dev/null 2>&1 || PKG_MGR="yum"

        log_info "Writing /etc/yum.repos.d/kubernetes.repo..."
        cat >/etc/yum.repos.d/kubernetes.repo <<EOF
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/${K8S_VER}/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/${K8S_VER}/rpm/repodata/repomd.xml.key
EOF

        log_info "Installing kubelet, kubeadm, kubectl..."
        ${PKG_MGR} install -y kubelet kubeadm kubectl
        ;;

    generic)
        log_error "Unsupported package manager for generic OS."
        ;;
esac

log_info "Enabling kubelet service..."
systemctl enable kubelet || true

log_success "Kubernetes binaries installed: $(kubeadm version -o short 2>/dev/null || echo "${K8S_VER}")"
