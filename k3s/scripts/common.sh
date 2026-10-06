#!/usr/bin/env bash
# ==============================================================================
# Common Helper Functions & Utilities
# ==============================================================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} ${BOLD}$*${NC}"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
    exit 1
}

log_header() {
    echo
    echo -e "${CYAN}====================================================================${NC}"
    echo -e "${CYAN}  $*${NC}"
    echo -e "${CYAN}====================================================================${NC}"
    echo
}

# Ensure root privileges
check_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        log_error "This script must be run as root or with sudo."
    fi
}

# Detect Linux Distribution
detect_os() {
    if [[ ! -f /etc/os-release ]]; then
        log_error "/etc/os-release not found. Unsupported operating system."
    fi

    # shellcheck disable=SC1091
    source /etc/os-release

    OS_ID="${ID:-unknown}"
    OS_VERSION="${VERSION_ID:-unknown}"

    case "${OS_ID}" in
        ubuntu|debian)
            OS_FAMILY="debian"
            ;;
        rhel|rocky|almalinux|centos|fedora|ol)
            OS_FAMILY="rhel"
            ;;
        *)
            log_warn "Distribution '${OS_ID}' recognized as generic Linux."
            OS_FAMILY="generic"
            ;;
    esac

    log_info "Detected OS: ${OS_ID} (${OS_FAMILY} family, version ${OS_VERSION})"
}

# Detect WSL2 environment
detect_wsl() {
    if grep -qi microsoft /proc/version 2>/dev/null; then
        IS_WSL=true
        log_warn "Windows WSL2 environment detected."
        log_warn "K3s is executing within WSL2 Linux container."
        
        # Check systemd in WSL2
        if ! pidof systemd >/dev/null 2>&1 && [[ "$(ps -p 1 -o comm= 2>/dev/null)" != "systemd" ]]; then
            log_warn "WSL2 does not appear to have systemd initialized as PID 1."
            log_warn "Ensure /etc/wsl.conf contains:"
            echo -e "    [boot]\n    systemd=true"
            log_warn "Then run 'wsl.exe --shutdown' from PowerShell and reopen your terminal."
        fi
    else
        IS_WSL=false
    fi
}

# Detect primary node IPv4
detect_node_ip() {
    local detected_ip=""
    detected_ip=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1); exit}')
    if [[ -z "${detected_ip}" ]]; then
        detected_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    fi

    if [[ -n "${NODE_IP:-}" ]]; then
        # Check if the user-specified NODE_IP exists on a local interface
        if ! ip -o addr show 2>/dev/null | grep -qw "${NODE_IP}"; then
            log_warn "Configured NODE_IP '${NODE_IP}' was not found on any active network interface of this host!"
            log_warn "Active host interfaces detected:"
            ip -o -4 addr show 2>/dev/null | awk '{print "    - " $2 ": " $4}' || true
            log_warn "K3s CNI networking requires NODE_IP to match a local host interface. If this IP was copied from documentation examples, consider running without NODE_IP (which auto-detects: ${detected_ip})."
        fi
    else
        NODE_IP="${detected_ip}"
    fi

    [[ -n "${NODE_IP}" ]] || log_error "Unable to auto-detect node IP. Please export NODE_IP manually."
    log_info "Node IP: ${NODE_IP}"
}

# Load environment configuration files
load_config() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local root_dir
    root_dir="$(cd "${script_dir}/.." && pwd)"

    local cluster_cfg="${root_dir}/config/cluster.env"
    local server_cfg="${root_dir}/config/server.env"
    local worker_cfg="${root_dir}/config/worker.env"

    if [[ -f "${cluster_cfg}" ]]; then
        # shellcheck disable=SC1090
        source "${cluster_cfg}"
    fi

    if [[ "${ROLE:-}" =~ ^server || "${1:-}" =~ ^server ]]; then
        if [[ -f "${server_cfg}" ]]; then
            # shellcheck disable=SC1090
            source "${server_cfg}"
        fi
    fi

    if [[ "${ROLE:-}" == "worker" || "${1:-}" == "worker" ]]; then
        if [[ -f "${worker_cfg}" ]]; then
            # shellcheck disable=SC1090
            source "${worker_cfg}"
        fi
    fi
}

# Parse comma/space separated SANs into array of flags
format_san_flags() {
    local sans_str="$1"
    local flags=""
    IFS=', ' read -r -a sans_array <<< "${sans_str}"
    for san in "${sans_array[@]}"; do
        if [[ -n "${san}" ]]; then
            flags+=" --tls-san=${san}"
        fi
    done
    echo "${flags}"
}

# Parse comma/space separated labels into array of flags
format_label_flags() {
    local labels_str="$1"
    local flags=""
    IFS=', ' read -r -a labels_array <<< "${labels_str}"
    for lbl in "${labels_array[@]}"; do
        if [[ -n "${lbl}" ]]; then
            flags+=" --node-label=${lbl}"
        fi
    done
    echo "${flags}"
}

# Parse comma/space separated taints into array of flags
format_taint_flags() {
    local taints_str="$1"
    local flags=""
    IFS=', ' read -r -a taints_array <<< "${taints_str}"
    for tnt in "${taints_array[@]}"; do
        if [[ -n "${tnt}" ]]; then
            flags+=" --node-taint=${tnt}"
        fi
    done
    echo "${flags}"
}
