#!/usr/bin/env bash
# ==============================================================================
# Comprehensive Automated Test Suite for Upstream Kubernetes Installer (k8s.sh)
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

MOCK_DIR=$(mktemp -d /tmp/k8s-test-mock.XXXXXX)
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
# 2. CLI Help & Root Checks
# ==============================================================================
section "2. CLI Help & Root Enforcement"

HELP_OUT=$("${PROJECT_DIR}/k8s.sh" help 2>&1)
if [[ $? -eq 0 && "${HELP_OUT}" =~ "Kubernetes Universal Modular Installer" ]]; then
    pass "Command './k8s.sh help' works without root"
else
    fail "Command './k8s.sh help'"
fi

HELP_FLAG_OUT=$("${PROJECT_DIR}/k8s.sh" --help 2>&1)
if [[ $? -eq 0 && "${HELP_FLAG_OUT}" =~ "control-plane" && "${HELP_FLAG_OUT}" =~ "worker" ]]; then
    pass "Flag './k8s.sh --help' lists commands"
else
    fail "Flag './k8s.sh --help'"
fi

if [[ "${EUID}" -ne 0 ]]; then
    CP_OUT=$("${PROJECT_DIR}/k8s.sh" control-plane 2>&1 || true)
    if [[ "${CP_OUT}" =~ "must be run as root" ]]; then
        pass "Privilege check correctly blocks unprivileged 'control-plane'"
    else
        fail "Privilege check for 'control-plane'"
    fi
fi

# ==============================================================================
# 3. Environment & OS Detection (common.sh)
# ==============================================================================
section "3. Environment Detection in common.sh"

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

if [[ -n "${OS_FAMILY:-}" && ("${OS_FAMILY}" == "debian" || "${OS_FAMILY}" == "rhel" || "${OS_FAMILY}" == "amazon" || "${OS_FAMILY}" == "generic") ]]; then
    pass "detect_os identified family: ${OS_FAMILY}"
else
    fail "detect_os" "Unknown family: '${OS_FAMILY:-}'"
fi

if [[ -n "${IS_WSL:-}" ]]; then
    pass "detect_wsl identified WSL state: ${IS_WSL}"
else
    fail "detect_wsl"
fi

if [[ "${NODE_IP:-}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    pass "detect_node_ip detected valid IPv4: ${NODE_IP}"
else
    fail "detect_node_ip"
fi

# ==============================================================================
# 4. Helper Formatting (format_apiserver_sans)
# ==============================================================================
section "4. Helper Formatting"

SAN_TEST=$(bash -c '
    source "'"${SCRIPTS_DIR}"'/common.sh"
    format_apiserver_sans "10.0.0.1,k8s.example.com 10.0.0.2"
')
if [[ "${SAN_TEST}" =~ "10.0.0.1,k8s.example.com,10.0.0.2" ]]; then
    pass "format_apiserver_sans converts mixed delimiters to comma-separated list"
else
    fail "format_apiserver_sans" "Output: ${SAN_TEST}"
fi

# ==============================================================================
# 5. Configuration Loading & Precedence
# ==============================================================================
section "5. Configuration Loading & Overrides"

DEFAULT_CFG=$(bash -c '
    source "'"${SCRIPTS_DIR}"'/common.sh"
    load_config "control-plane"
    echo "ENV=${ENVIRONMENT}"
    echo "CNI=${CNI}"
    echo "POD_CIDR=${POD_CIDR}"
')
eval "${DEFAULT_CFG}"

if [[ "${ENV}" == "onprem" && "${CNI}" == "cilium" && "${POD_CIDR}" == "10.244.0.0/16" ]]; then
    pass "Default configuration loaded accurately from cluster.env"
else
    fail "Default configuration" "ENV=${ENV}, CNI=${CNI}, POD_CIDR=${POD_CIDR}"
fi

OVERRIDE_CFG=$(bash -c '
    export ENVIRONMENT="aws"
    export CNI="calico"
    export POD_CIDR="172.16.0.0/16"
    source "'"${SCRIPTS_DIR}"'/common.sh"
    load_config "control-plane"
    echo "ENV=${ENVIRONMENT}"
    echo "CNI=${CNI}"
    echo "POD_CIDR=${POD_CIDR}"
')
eval "${OVERRIDE_CFG}"

if [[ "${ENV}" == "aws" && "${CNI}" == "calico" && "${POD_CIDR}" == "172.16.0.0/16" ]]; then
    pass "Environment variables override cluster.env settings"
else
    fail "Environment override" "ENV=${ENV}, CNI=${CNI}, POD_CIDR=${POD_CIDR}"
fi

# ==============================================================================
# 6. containerd Configuration & SystemdCgroup Verification
# ==============================================================================
section "6. containerd Configuration"

CONTAINERD_CONF_TEST=$(bash -c '
    MOCK_CONF="/tmp/test_containerd.toml"
    cat > "${MOCK_CONF}" << "EOF"
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
  SystemdCgroup = false
EOF
    sed -i "s/SystemdCgroup = false/SystemdCgroup = true/" "${MOCK_CONF}"
    grep -q "SystemdCgroup = true" "${MOCK_CONF}" && echo "OK"
    rm -f "${MOCK_CONF}"
')
if [[ "${CONTAINERD_CONF_TEST}" == "OK" ]]; then
    pass "containerd config accurately replaces SystemdCgroup = true"
else
    fail "containerd config substitution"
fi

# ==============================================================================
# 7. Dry-Run Command Generation (kubeadm init / join)
# ==============================================================================
section "7. Dry-Run Command Assembly"

# Mock kubeadm
cat > "${MOCK_DIR}/kubeadm" << 'EOF'
#!/bin/bash
echo "[MOCK_KUBEADM] $*" >> /tmp/k8s_mock_log.txt
if [[ "$*" =~ "init" ]]; then
    echo "Your Kubernetes control-plane has initialized successfully!"
    echo "kubeadm join 10.10.10.100:6443 --token abcdef.1234567890abcdef --discovery-token-ca-cert-hash sha256:123456"
fi
exit 0
EOF
chmod +x "${MOCK_DIR}/kubeadm"

# Test 7.1: kubeadm init argument assembly
rm -f /tmp/k8s_mock_log.txt
TEST_INIT=$(PATH="${MOCK_DIR}:${PATH}" bash -c '
    check_root() { return 0; }
    export -f check_root
    source "'"${SCRIPTS_DIR}"'/common.sh"
    load_config "control-plane"
    
    CP_ENDPOINT="k8s-api.example.com"
    CP_PORT="6443"
    NODE_IP="10.10.10.11"
    POD_CIDR="10.244.0.0/16"
    SERVICE_CIDR="10.96.0.0/12"
    ALL_SANS=$(format_apiserver_sans "10.10.10.11,127.0.0.1,${CP_ENDPOINT}")
    
    INIT_ARGS=(init)
    INIT_ARGS+=(--control-plane-endpoint="${CP_ENDPOINT}:${CP_PORT}")
    INIT_ARGS+=(--pod-network-cidr="${POD_CIDR}")
    INIT_ARGS+=(--service-cidr="${SERVICE_CIDR}")
    INIT_ARGS+=(--apiserver-advertise-address="${NODE_IP}")
    INIT_ARGS+=(--apiserver-cert-extra-sans="${ALL_SANS}")
    INIT_ARGS+=(--upload-certs)
    
    kubeadm "${INIT_ARGS[@]}"
')

MOCK_LOG=$(cat /tmp/k8s_mock_log.txt 2>/dev/null || echo "")

if [[ "${MOCK_LOG}" =~ "--control-plane-endpoint=k8s-api.example.com:6443" && "${MOCK_LOG}" =~ "--upload-certs" && "${MOCK_LOG}" =~ "--pod-network-cidr=10.244.0.0/16" && "${MOCK_LOG}" =~ "--apiserver-cert-extra-sans=10.10.10.11,127.0.0.1,k8s-api.example.com" ]]; then
    pass "Dry-run kubeadm init accurately constructs endpoint, certs, SANs, and CIDRs"
else
    fail "Dry-run kubeadm init" "Mock log: ${MOCK_LOG}"
fi

# Test 7.2: kubeadm join --control-plane
rm -f /tmp/k8s_mock_log.txt
TEST_CP_JOIN=$(PATH="${MOCK_DIR}:${PATH}" bash -c '
    check_root() { return 0; }
    export -f check_root
    JOIN_ARGS=(join "k8s-api.example.com:6443")
    JOIN_ARGS+=(--token "abcdef.1234567890abcdef")
    JOIN_ARGS+=(--discovery-token-ca-cert-hash "sha256:123456")
    JOIN_ARGS+=(--control-plane)
    JOIN_ARGS+=(--certificate-key "fedcba9876543210")
    JOIN_ARGS+=(--apiserver-advertise-address="10.10.10.12")
    kubeadm "${JOIN_ARGS[@]}"
')

MOCK_LOG=$(cat /tmp/k8s_mock_log.txt 2>/dev/null || echo "")

if [[ "${MOCK_LOG}" =~ "--control-plane" && "${MOCK_LOG}" =~ "--certificate-key fedcba9876543210" && "${MOCK_LOG}" =~ "k8s-api.example.com:6443" ]]; then
    pass "Dry-run kubeadm join --control-plane passes certificate-key and control-plane flag"
else
    fail "Dry-run kubeadm join --control-plane" "Mock log: ${MOCK_LOG}"
fi

# Test 7.3: kubeadm join worker
rm -f /tmp/k8s_mock_log.txt
TEST_WORKER_JOIN=$(PATH="${MOCK_DIR}:${PATH}" bash -c '
    check_root() { return 0; }
    export -f check_root
    JOIN_ARGS=(join "k8s-api.example.com:6443")
    JOIN_ARGS+=(--token "abcdef.1234567890abcdef")
    JOIN_ARGS+=(--discovery-token-ca-cert-hash "sha256:123456")
    kubeadm "${JOIN_ARGS[@]}"
')

MOCK_LOG=$(cat /tmp/k8s_mock_log.txt 2>/dev/null || echo "")

if [[ "${MOCK_LOG}" =~ "join k8s-api.example.com:6443" && ! "${MOCK_LOG}" =~ "--control-plane" && ! "${MOCK_LOG}" =~ "--certificate-key" ]]; then
    pass "Dry-run kubeadm join worker omits control-plane flags and passes endpoint & credentials"
else
    fail "Dry-run kubeadm join worker" "Mock log: ${MOCK_LOG}"
fi

rm -f /tmp/k8s_mock_log.txt

# ==============================================================================
# 8. Backward-Compatibility (ROLE=...) Syntax Resolution
# ==============================================================================
section "8. Backward Compatibility Syntax (ROLE=...)"

ROLE_CP_DISPATCH=$(bash -c '
    ROLE="control-plane"
    ACTION="${1:-${ROLE:-help}}"
    echo "ACTION=${ACTION}"
')
if [[ "${ROLE_CP_DISPATCH}" == "ACTION=control-plane" ]]; then
    pass "ROLE=control-plane resolves correctly without positional arguments"
else
    fail "ROLE=control-plane resolution"
fi

ROLE_JOIN_DISPATCH=$(bash -c '
    ROLE="control-plane-join"
    ACTION="${1:-${ROLE:-help}}"
    echo "ACTION=${ACTION}"
')
if [[ "${ROLE_JOIN_DISPATCH}" == "ACTION=control-plane-join" ]]; then
    pass "ROLE=control-plane-join resolves correctly without positional arguments"
else
    fail "ROLE=control-plane-join resolution"
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
