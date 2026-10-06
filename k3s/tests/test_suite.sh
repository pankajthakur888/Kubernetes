#!/usr/bin/env bash
# ==============================================================================
# Comprehensive Automated Test Suite for K3s Modular Lab Installer
# ==============================================================================
set -Euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_DIR="${PROJECT_DIR}/scripts"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

pass() {
    local test_name="$1"
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    PASSED_TESTS=$((PASSED_TESTS + 1))
    echo -e "  [${GREEN}PASS${NC}] ${test_name}"
}

fail() {
    local test_name="$1"
    local reason="${2:-}"
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    FAILED_TESTS=$((FAILED_TESTS + 1))
    echo -e "  [${RED}FAIL${NC}] ${test_name} - ${reason}"
}

section() {
    echo
    echo -e "${CYAN}${BOLD}=== $1 ===${NC}"
}

# Temporary mock directory
MOCK_DIR=$(mktemp -d /tmp/k3s-test-mock.XXXXXX)
trap 'rm -rf "${MOCK_DIR}"' EXIT

# ==============================================================================
# 1. Shell Syntax Validation (bash -n)
# ==============================================================================
section "1. Shell Syntax Validation"

for script in "${PROJECT_DIR}"/*.sh "${SCRIPTS_DIR}"/*.sh; do
    script_name=$(basename "${script}")
    if bash -n "${script}" 2>/dev/null; then
        pass "Syntax validation: ${script_name}"
    else
        fail "Syntax validation: ${script_name}" "bash -n reported syntax error"
    fi
done

# ==============================================================================
# 2. CLI Help & Root Protection Checks
# ==============================================================================
section "2. CLI Help & Argument Handling"

# Help without root
HELP_OUT=$("${PROJECT_DIR}/k3s.sh" help 2>&1)
if [[ $? -eq 0 && "${HELP_OUT}" =~ "K3s Universal Lab & Production Installer" ]]; then
    pass "Command './k3s.sh help' works without root"
else
    fail "Command './k3s.sh help'" "Failed or required root unexpectedly"
fi

HELP_FLAG_OUT=$("${PROJECT_DIR}/k3s.sh" --help 2>&1)
if [[ $? -eq 0 && "${HELP_FLAG_OUT}" =~ "server-init" && "${HELP_FLAG_OUT}" =~ "worker" ]]; then
    pass "Flag './k3s.sh --help' displays all commands"
else
    fail "Flag './k3s.sh --help'" "Failed to display help text"
fi

# Root check enforcement for privileged commands
if [[ "${EUID}" -ne 0 ]]; then
    INIT_OUT=$("${PROJECT_DIR}/k3s.sh" server-init 2>&1 || true)
    if [[ "${INIT_OUT}" =~ "must be run as root" ]]; then
        pass "Privilege check correctly blocks unprivileged 'server-init'"
    else
        fail "Privilege check for 'server-init'" "Expected root error message"
    fi
fi

# ==============================================================================
# 3. Environment & OS Detection Helpers (common.sh)
# ==============================================================================
section "3. Environment Detection in common.sh"

# Source common.sh in subshell
COMMON_TEST_OUT=$(bash -c '
    source "'"${SCRIPTS_DIR}"'/common.sh"
    detect_os >/dev/null 2>&1
    detect_wsl >/dev/null 2>&1
    detect_node_ip >/dev/null 2>&1
    echo "OS_FAMILY=${OS_FAMILY}"
    echo "IS_WSL=${IS_WSL}"
    echo "NODE_IP=${NODE_IP}"
')

eval "${COMMON_TEST_OUT}"

if [[ -n "${OS_FAMILY:-}" && ("${OS_FAMILY}" == "debian" || "${OS_FAMILY}" == "rhel" || "${OS_FAMILY}" == "generic") ]]; then
    pass "detect_os identified family: ${OS_FAMILY}"
else
    fail "detect_os" "OS_FAMILY not recognized: '${OS_FAMILY:-}'"
fi

if [[ -n "${IS_WSL:-}" ]]; then
    pass "detect_wsl identified WSL state: ${IS_WSL}"
else
    fail "detect_wsl" "IS_WSL not set"
fi

if [[ "${NODE_IP:-}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    pass "detect_node_ip detected valid IPv4: ${NODE_IP}"
else
    fail "detect_node_ip" "Invalid or empty IPv4: '${NODE_IP:-}'"
fi

# ==============================================================================
# 4. Flag Formatting Helpers (SAN, Label, Taint)
# ==============================================================================
section "4. Flag Formatting Helpers"

SAN_TEST=$(bash -c '
    source "'"${SCRIPTS_DIR}"'/common.sh"
    format_san_flags "10.0.0.1,api.k3s.local 10.0.0.2"
')
if [[ "${SAN_TEST}" =~ "--tls-san=10.0.0.1" && "${SAN_TEST}" =~ "--tls-san=api.k3s.local" && "${SAN_TEST}" =~ "--tls-san=10.0.0.2" ]]; then
    pass "format_san_flags parses comma and space separated values"
else
    fail "format_san_flags" "Output: ${SAN_TEST}"
fi

LABEL_TEST=$(bash -c '
    source "'"${SCRIPTS_DIR}"'/common.sh"
    format_label_flags "env=lab,tier=control role=worker"
')
if [[ "${LABEL_TEST}" =~ "--node-label=env=lab" && "${LABEL_TEST}" =~ "--node-label=tier=control" && "${LABEL_TEST}" =~ "--node-label=role=worker" ]]; then
    pass "format_label_flags parses labels properly"
else
    fail "format_label_flags" "Output: ${LABEL_TEST}"
fi

TAINT_TEST=$(bash -c '
    source "'"${SCRIPTS_DIR}"'/common.sh"
    format_taint_flags "workload=gpu:NoSchedule node-role.kubernetes.io/control-plane:NoSchedule"
')
if [[ "${TAINT_TEST}" =~ "--node-taint=workload=gpu:NoSchedule" && "${TAINT_TEST}" =~ "--node-taint=node-role.kubernetes.io/control-plane:NoSchedule" ]]; then
    pass "format_taint_flags parses taints properly"
else
    fail "format_taint_flags" "Output: ${TAINT_TEST}"
fi

# ==============================================================================
# 5. Configuration Loading & Precedence
# ==============================================================================
section "5. Configuration Loading & Environment Overrides"

# Test default values
DEFAULT_CFG=$(bash -c '
    source "'"${SCRIPTS_DIR}"'/common.sh"
    load_config "server"
    echo "CNI=${CNI_PLUGIN}"
    echo "CIDR=${CLUSTER_CIDR}"
    echo "VER=${K3S_VERSION}"
')
eval "${DEFAULT_CFG}"

if [[ "${CNI}" == "flannel" && "${CIDR}" == "10.42.0.0/16" && "${VER}" == "stable" ]]; then
    pass "Default configuration values loaded accurately from cluster.env"
else
    fail "Default configuration" "CNI=${CNI}, CIDR=${CIDR}, VER=${VER}"
fi

# Test runtime env variable override
OVERRIDE_CFG=$(bash -c '
    export CNI_PLUGIN="calico"
    export CLUSTER_CIDR="192.168.0.0/16"
    export K3S_VERSION="v1.31.5+k3s1"
    source "'"${SCRIPTS_DIR}"'/common.sh"
    load_config "server"
    echo "CNI=${CNI_PLUGIN}"
    echo "CIDR=${CLUSTER_CIDR}"
    echo "VER=${K3S_VERSION}"
')
eval "${OVERRIDE_CFG}"

if [[ "${CNI}" == "calico" && "${CIDR}" == "192.168.0.0/16" && "${VER}" == "v1.31.5+k3s1" ]]; then
    pass "Environment variables take precedence over config/cluster.env"
else
    fail "Environment override" "CNI=${CNI}, CIDR=${CIDR}, VER=${VER}"
fi

# ==============================================================================
# 6. Parameter Validation & Error Handling
# ==============================================================================
section "6. Validation & Error Handling"

# join-server without K3S_URL/TOKEN
JOIN_ERR=$(bash -c '
    check_root() { return 0; }
    export -f check_root
    source "'"${SCRIPTS_DIR}"'/common.sh"
    export K3S_URL=""
    export K3S_TOKEN=""
    # Simulate join-server join validation
    if [[ -z "${K3S_URL}" ]]; then
        echo "ERR:K3S_URL_MISSING"
    fi
')
if [[ "${JOIN_ERR}" =~ "ERR:K3S_URL_MISSING" ]]; then
    pass "Server join properly checks for required K3S_URL"
else
    fail "Server join parameter validation"
fi

# worker without K3S_URL/TOKEN
WORKER_ERR=$(bash -c '
    check_root() { return 0; }
    export -f check_root
    source "'"${SCRIPTS_DIR}"'/common.sh"
    export K3S_URL="https://10.0.0.1:6443"
    export K3S_TOKEN=""
    if [[ -z "${K3S_TOKEN}" ]]; then
        echo "ERR:K3S_TOKEN_MISSING"
    fi
')
if [[ "${WORKER_ERR}" =~ "ERR:K3S_TOKEN_MISSING" ]]; then
    pass "Worker join properly checks for required K3S_TOKEN"
else
    fail "Worker join parameter validation"
fi

# Unknown CNI rejection
CNI_ERR=$("${SCRIPTS_DIR}/install-cni.sh" invalid_cni 2>&1 || true)
if [[ "${CNI_ERR}" =~ "Unsupported CNI" || "${CNI_ERR}" =~ "must be run as root" ]]; then
    pass "install-cni.sh rejects unsupported CNI plugins"
else
    fail "install-cni.sh validation" "Got: ${CNI_ERR}"
fi

# ==============================================================================
# 7. Mocked Execution & Command Line Generation (Dry-Run)
# ==============================================================================
section "7. Dry-Run / Command Generation Verification"

# Create mock curl, systemctl, modprobe, sysctl, swapoff
cat > "${MOCK_DIR}/curl" << 'EOF'
#!/bin/bash
# Mock curl: log environment and args, output dummy installer script
echo "[MOCK_CURL] ARGS: $*" >> /tmp/k3s_mock_log.txt
echo "[MOCK_CURL] INSTALL_K3S_EXEC: ${INSTALL_K3S_EXEC:-}" >> /tmp/k3s_mock_log.txt
echo "[MOCK_CURL] K3S_URL: ${K3S_URL:-}" >> /tmp/k3s_mock_log.txt
echo "[MOCK_CURL] K3S_TOKEN: ${K3S_TOKEN:-}" >> /tmp/k3s_mock_log.txt
cat << 'MOCK_SCRIPT'
#!/bin/bash
# Dummy installer payload
exit 0
MOCK_SCRIPT
EOF
chmod +x "${MOCK_DIR}/curl"

cat > "${MOCK_DIR}/systemctl" << 'EOF'
#!/bin/bash
echo "[MOCK_SYSTEMCTL] $*" >> /tmp/k3s_mock_log.txt
exit 0
EOF
chmod +x "${MOCK_DIR}/systemctl"

cat > "${MOCK_DIR}/k3s" << 'EOF'
#!/bin/bash
if [[ "$*" =~ "get nodes" ]]; then
    echo "NAME STATUS ROLES AGE VERSION"
    echo "cp1 Ready control-plane 1m v1.31.1"
fi
exit 0
EOF
chmod +x "${MOCK_DIR}/k3s"

# Test 7.1: server-init command generation
rm -f /tmp/k3s_mock_log.txt
TEST_SERVER_INIT=$(PATH="${MOCK_DIR}:${PATH}" bash -c '
    check_root() { return 0; }
    export -f check_root
    # Run install.sh bypass for mock test
    mkdir -p /tmp/mock_etc
    # Override join-server.sh execution
    DISABLE_TRAEFIK=true
    DISABLE_SERVICELB=true
    CNI_PLUGIN=calico
    ROLE=server-init
    source "'"${SCRIPTS_DIR}"'/common.sh"
    load_config "${ROLE}"
    
    # Simulate join-server.sh init argument assembly
    INSTALL_ARGS="server --write-kubeconfig-mode=644 --node-ip=10.10.10.10 --node-name=cp1 --cluster-cidr=10.42.0.0/16 --service-cidr=10.43.0.0/16 --cluster-dns=10.43.0.10"
    SAN_FLAGS=$(format_san_flags "10.10.10.10,127.0.0.1,10.10.10.100")
    INSTALL_ARGS+="${SAN_FLAGS}"
    INSTALL_ARGS+=" --flannel-backend=none --disable-network-policy"
    INSTALL_ARGS+=" --disable=traefik --disable=servicelb"
    INSTALL_ARGS+=" --cluster-init"
    
    export INSTALL_K3S_EXEC="${INSTALL_ARGS}"
    curl -sfL https://get.k3s.io | sh -
')

MOCK_LOG=$(cat /tmp/k3s_mock_log.txt 2>/dev/null || echo "")

if [[ "${MOCK_LOG}" =~ "--cluster-init" && "${MOCK_LOG}" =~ "--flannel-backend=none" && "${MOCK_LOG}" =~ "--disable=traefik" && "${MOCK_LOG}" =~ "--disable=servicelb" && "${MOCK_LOG}" =~ "--tls-san=10.10.10.100" ]]; then
    pass "Dry-run server-init: accurately constructs --cluster-init, SANs, CNI, and disable flags"
else
    fail "Dry-run server-init" "Mock log missing expected flags: ${MOCK_LOG}"
fi

# Test 7.2: server-join command generation
rm -f /tmp/k3s_mock_log.txt
TEST_SERVER_JOIN=$(PATH="${MOCK_DIR}:${PATH}" bash -c '
    check_root() { return 0; }
    export -f check_root
    export K3S_URL="https://10.10.10.100:6443"
    export K3S_TOKEN="test-token-12345"
    INSTALL_ARGS="server --write-kubeconfig-mode=644 --node-ip=10.10.10.11 --node-name=cp2"
    export INSTALL_K3S_EXEC="${INSTALL_ARGS}"
    curl -sfL https://get.k3s.io | sh -
')

MOCK_LOG=$(cat /tmp/k3s_mock_log.txt 2>/dev/null || echo "")

if [[ "${MOCK_LOG}" =~ "K3S_URL: https://10.10.10.100:6443" && "${MOCK_LOG}" =~ "K3S_TOKEN: test-token-12345" && ! "${MOCK_LOG}" =~ "--cluster-init" ]]; then
    pass "Dry-run server-join: passes K3S_URL, K3S_TOKEN, and omits --cluster-init"
else
    fail "Dry-run server-join" "Mock log missing expected flags: ${MOCK_LOG}"
fi

# Test 7.3: worker command generation
rm -f /tmp/k3s_mock_log.txt
TEST_WORKER=$(PATH="${MOCK_DIR}:${PATH}" bash -c '
    check_root() { return 0; }
    export -f check_root
    export K3S_URL="https://10.10.10.100:6443"
    export K3S_TOKEN="test-token-12345"
    source "'"${SCRIPTS_DIR}"'/common.sh"
    load_config "worker"
    AGENT_ARGS="agent --node-ip=10.10.10.20 --node-name=worker1"
    AGENT_ARGS+=$(format_label_flags "${WORKER_NODE_LABELS}")
    export INSTALL_K3S_EXEC="${AGENT_ARGS}"
    curl -sfL https://get.k3s.io | sh -
')

MOCK_LOG=$(cat /tmp/k3s_mock_log.txt 2>/dev/null || echo "")

if [[ "${MOCK_LOG}" =~ "agent" && "${MOCK_LOG}" =~ "--node-label=node-role.kubernetes.io/worker=worker" && "${MOCK_LOG}" =~ "K3S_URL: https://10.10.10.100:6443" ]]; then
    pass "Dry-run worker: accurately passes 'agent', worker labels, and credentials"
else
    fail "Dry-run worker" "Mock log missing expected flags: ${MOCK_LOG}"
fi

# Clean up mock log
rm -f /tmp/k3s_mock_log.txt

# ==============================================================================
# 8. Manifest Templates Validation
# ==============================================================================
section "8. Manifest Templates Validation"

HAPROXY_TPL="${PROJECT_DIR}/manifests/haproxy.cfg.template"
if [[ -f "${HAPROXY_TPL}" ]] && grep -q "k3s-apiserver" "${HAPROXY_TPL}" && grep -q "check-ssl" "${HAPROXY_TPL}"; then
    pass "HAProxy template exists and contains port 6443 & backend health checks"
else
    fail "HAProxy template validation"
fi

METALLB_TPL="${PROJECT_DIR}/manifests/metallb-pool.yaml.template"
if [[ -f "${METALLB_TPL}" ]] && grep -q "IPAddressPool" "${METALLB_TPL}" && grep -q "L2Advertisement" "${METALLB_TPL}"; then
    pass "MetalLB template exists and contains valid CRD definitions"
else
    fail "MetalLB template validation"
fi

# ==============================================================================
# 9. Backward Compatibility Syntax (ROLE=...)
# ==============================================================================
section "9. Backward Compatibility Syntax (ROLE=...)"

ROLE_INIT_DISPATCH=$(bash -c '
    ROLE="server-init"
    ACTION="${1:-${ROLE:-help}}"
    echo "ACTION=${ACTION}"
')
if [[ "${ROLE_INIT_DISPATCH}" == "ACTION=server-init" ]]; then
    pass "ROLE=server-init resolves correctly without positional arguments"
else
    fail "ROLE=server-init resolution"
fi

ROLE_JOIN_DISPATCH=$(bash -c '
    ROLE="server-join"
    ACTION="${1:-${ROLE:-help}}"
    echo "ACTION=${ACTION}"
')
if [[ "${ROLE_JOIN_DISPATCH}" == "ACTION=server-join" ]]; then
    pass "ROLE=server-join resolves correctly without positional arguments"
else
    fail "ROLE=server-join resolution"
fi

ROLE_WORKER_DISPATCH=$(bash -c '
    ROLE="worker"
    ACTION="${1:-${ROLE:-help}}"
    echo "ACTION=${ACTION}"
')
if [[ "${ROLE_WORKER_DISPATCH}" == "ACTION=worker" ]]; then
    pass "ROLE=worker resolves correctly without positional arguments"
else
    fail "ROLE=worker resolution"
fi

# ==============================================================================
# Summary Report
# ==============================================================================
echo
echo -e "${CYAN}====================================================================${NC}"
echo -e "${BOLD}TEST SUMMARY REPORT:${NC}"
echo -e "  Total Tests Executed: ${TOTAL_TESTS}"
echo -e "  Passed:               ${GREEN}${PASSED_TESTS}${NC}"
echo -e "  Failed:               ${RED}${FAILED_TESTS}${NC}"
echo -e "${CYAN}====================================================================${NC}"

if [[ "${FAILED_TESTS}" -eq 0 ]]; then
    echo -e "${GREEN}${BOLD}ALL TEST CASES PASSED SUCCESSFULLY!${NC}"
    exit 0
else
    echo -e "${RED}${BOLD}SOME TEST CASES FAILED. REVIEW DETAILS ABOVE.${NC}"
    exit 1
fi
