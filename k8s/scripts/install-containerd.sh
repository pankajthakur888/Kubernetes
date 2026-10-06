#!/usr/bin/env bash
# ==============================================================================
# containerd Runtime Installer & SystemdCgroup Configuration
# ==============================================================================
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"

check_root
detect_os
load_config

log_header "Installing and Configuring containerd CRI"

case "${OS_FAMILY}" in
    debian)
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -y
        apt-get install -y containerd
        ;;
    rhel|amazon)
        PKG_MGR="dnf"
        command -v dnf >/dev/null 2>&1 || PKG_MGR="yum"
        ${PKG_MGR} install -y containerd || ${PKG_MGR} install -y containerd.io || log_warn "Could not install containerd via package manager directly."
        ;;
    generic)
        log_warn "Generic OS: ensure containerd package is installed."
        ;;
esac

log_info "Configuring containerd default configuration..."
mkdir -p /etc/containerd

if command -v containerd >/dev/null 2>&1; then
    containerd config default > /etc/containerd/config.toml
else
    # Create fallback config.toml if containerd binary is not yet available in path
    cat >/etc/containerd/config.toml <<EOF
version = 2
[plugins]
  [plugins."io.containerd.grpc.v1.cri"]
    [plugins."io.containerd.grpc.v1.cri".containerd]
      [plugins."io.containerd.grpc.v1.cri".containerd.runtimes]
        [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
          runtime_type = "io.containerd.runc.v2"
          [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
            SystemdCgroup = true
EOF
fi

# Kubernetes strictly recommends SystemdCgroup = true
log_info "Enabling SystemdCgroup = true in /etc/containerd/config.toml..."
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml || true

# Configure crictl
cat >/etc/crictl.yaml <<EOF
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 10
debug: false
EOF

log_info "Starting and enabling containerd service..."
systemctl daemon-reload || true
systemctl restart containerd || true
systemctl enable containerd || true

if systemctl is-active --quiet containerd 2>/dev/null; then
    log_success "containerd runtime is active and configured with SystemdCgroup=true."
else
    log_warn "containerd service started or will start once container runtime socket is initialized."
fi
