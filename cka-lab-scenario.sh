#!/usr/bin/env bash
#
# CKA Lab Scenario: Network Connectivity Production Issue
# This script sets up a broken network policy scenario on an existing Kubernetes/K3s cluster.
#

echo "============================================================"
echo " CKA Lab Scenario: Troubleshooting Network Connectivity"
echo "============================================================"

# Check if kubectl is available
if ! command -v kubectl >/dev/null 2>&1; then
    echo "[!] Error: kubectl is not installed or not in PATH."
    exit 1
fi

echo "[*] Creating namespace 'cka-prod'..."
kubectl create namespace cka-prod --dry-run=client -o yaml | kubectl apply -f - >/dev/null 2>&1

echo "[*] Deploying backend application (nginx)..."
kubectl run backend --image=nginx:alpine --labels="tier=backend" --namespace=cka-prod >/dev/null 2>&1
kubectl expose pod backend --port=80 --target-port=80 --namespace=cka-prod >/dev/null 2>&1

echo "[*] Deploying frontend application (curl shell)..."
kubectl run frontend --image=curlimages/curl --labels="tier=web" --namespace=cka-prod -- sleep 3600 >/dev/null 2>&1

echo "[*] Applying restrictive NetworkPolicy..."
cat << 'POLICY' | kubectl apply -f - >/dev/null 2>&1
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: backend-policy
  namespace: cka-prod
spec:
  podSelector:
    matchLabels:
      tier: backend
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          tier: frontend
    ports:
    - protocol: TCP
      port: 80
POLICY

echo "[*] Waiting for pods to become ready..."
kubectl wait --for=condition=Ready pod/backend -n cka-prod --timeout=60s >/dev/null 2>&1
kubectl wait --for=condition=Ready pod/frontend -n cka-prod --timeout=60s >/dev/null 2>&1

echo "============================================================"
echo " Scenario Setup Complete!"
echo " "
echo " PROBLEM STATEMENT:"
echo " The frontend application is trying to communicate with the backend application"
echo " over HTTP, but the requests are timing out. Both are in the 'cka-prod' namespace."
echo " "
echo " TASK:"
echo " Ensure the 'frontend' pod can successfully 'curl http://backend:80'."
echo " You may modify pod labels or the NetworkPolicy."
echo " "
echo " VERIFICATION COMMAND:"
echo " kubectl exec -it frontend -n cka-prod -- curl -m 5 http://backend:80"
echo " "
echo " SOLUTION / ANSWER KEY:"
echo " 1. Check pod labels: kubectl get pods -n cka-prod --show-labels"
echo "    (Notice frontend has label tier=web)"
echo " 2. Check policy: kubectl describe networkpolicy backend-policy -n cka-prod"
echo "    (Notice it allows ingress only from tier=frontend)"
echo " 3. Fix the label: kubectl label pod frontend -n cka-prod tier=frontend --overwrite"
echo "============================================================"
