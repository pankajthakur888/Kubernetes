# Modular Kubernetes (kubeadm / containerd) Production & Lab Suite

A reusable, production-ready Kubernetes installation and operations suite supporting on-prem bare-metal/VMs, AWS, GCP, and Azure. Built for DevOps engineers and **Certified Kubernetes Administrator (CKA)** exam excellence.

---

## 1. Architecture

```text
                           Internet / Clients
                                   │
                                   ▼
                    ┌──────────────────────────────┐
                    │      HA API Load Balancer    │
                    │   (HAProxy / NLB / VIP :6443)│
                    └──────────────┬───────────────┘
                                   │
            ┌──────────────────────┼──────────────────────┐
            │                      │                      │
            ▼                      ▼                      ▼
     ┌─────────────┐        ┌─────────────┐        ┌─────────────┐
     │     CP1     │◄──────►│     CP2     │◄──────►│     CP3     │
     │   (etcd)    │        │   (etcd)    │        │   (etcd)    │
     └──────┬──────┘        └──────┬──────┘        └──────┬──────┘
            │                      │                      │
            └──────────────────────┼──────────────────────┘
                                   │
            ┌──────────────────────┼──────────────────────┐
            │                      │                      │
            ▼                      ▼                      ▼
     ┌─────────────┐        ┌─────────────┐        ┌─────────────┐
     │   Worker 1  │        │   Worker 2  │        │   Worker 3  │
     │ (Workloads) │        │ (Workloads) │        │ (Workloads) │
     └─────────────┘        └─────────────┘        └─────────────┘

        Container Runtime: containerd (SystemdCgroup = true)
        Networking (CNI): Cilium (default) / Calico
        Storage (CSI): Local-Path (On-Prem) / EBS / GCE-PD / AzureDisk
```

---

## 2. Directory Layout

```text
k8s/
├── k8s.sh                         # Unified master CLI & orchestrator
├── uninstall.sh                   # kubeadm reset and interface/iptables cleanup
├── config/
│   ├── cluster.env                # Global settings (version, endpoint, CIDRs, CNI)
│   ├── control-plane.env          # Control plane settings (SANs, taints, advertise IP)
│   └── worker.env                 # Worker settings (labels, taints)
├── scripts/
│   ├── common.sh                  # Shared logging, OS detection, IP discovery
│   ├── install-prereqs.sh         # Swapoff, kernel modules (overlay/br_netfilter), sysctl
│   ├── install-containerd.sh      # containerd installation with SystemdCgroup=true
│   ├── install-k8s-packages.sh    # pkgs.k8s.io community repo (kubelet/kubeadm/kubectl)
│   ├── init-control-plane.sh      # Primary CP initialization (kubeadm init)
│   ├── join-control-plane.sh      # Control plane joiner (kubeadm join --control-plane)
│   ├── join-worker.sh             # Worker node joiner (kubeadm join)
│   ├── token.sh                   # Join command printer & certificate key uploader
│   ├── health-check.sh            # Diagnostics: etcd, static pods, nodes, CoreDNS
│   ├── install-cni.sh             # Calico (NetworkPolicies) & Cilium (eBPF)
│   ├── install-csi.sh             # CSI storage driver (Local-Path / Cloud CSI)
│   ├── install-metallb.sh         # MetalLB L2 Bare-Metal Load Balancer
│   └── setup-lb.sh                # HAProxy API Load Balancer setup
├── manifests/
│   └── haproxy.cfg.template       # HAProxy configuration template
├── terraform/
│   └── aws/main.tf                # Reference AWS VPC/NLB/EC2 architecture
├── tests/
│   └── test_suite.sh              # 30+ automated validation tests
└── README.md                      # Comprehensive reference guide
```

---

## 3. Quickstart: 3-Control-Plane HA Cluster + 3 Workers

Assuming:
- API VIP / Load Balancer: `k8s-api.lab.local:6443` (e.g. `10.10.10.100`)
- Control Planes: `CP1 (10.10.10.11)`, `CP2 (10.10.10.12)`, `CP3 (10.10.10.13)`
- Workers: `W1 (10.10.10.21)`, `W2 (10.10.10.22)`, `W3 (10.10.10.23)`

### Step 1: On Load Balancer Node
```bash
sudo ./k8s.sh lb 10.10.10.11 10.10.10.12 10.10.10.13
```

### Step 2: On CP1 (Initialize Control Plane)
```bash
sudo ROLE=control-plane \
     ENVIRONMENT=onprem \
     CONTROL_PLANE_ENDPOINT=k8s-api.lab.local \
     NODE_IP=10.10.10.11 \
     CNI=cilium \
     ./k8s.sh
```

Retrieve the cluster join commands and cert key:
```bash
sudo ./k8s.sh token
```

### Step 3: On CP2 & CP3 (Join Control Plane)
```bash
sudo ROLE=control-plane-join \
     CONTROL_PLANE_ENDPOINT=k8s-api.lab.local \
     NODE_IP=10.10.10.12 \
     JOIN_TOKEN="<TOKEN>" \
     DISCOVERY_TOKEN_CA_CERT_HASH="<HASH>" \
     CERTIFICATE_KEY="<CERT_KEY>" \
     ./k8s.sh
```

### Step 4: On Worker Nodes (W1, W2, W3)
```bash
sudo ROLE=worker \
     CONTROL_PLANE_ENDPOINT=k8s-api.lab.local \
     JOIN_TOKEN="<TOKEN>" \
     DISCOVERY_TOKEN_CA_CERT_HASH="<HASH>" \
     ./k8s.sh
```

### Step 5: Verify Health
```bash
sudo ./k8s.sh health-check
```

---

## 4. Multi-Cloud Architecture (Terraform + k8s.sh)

To keep architectures modular and clean:
1. **Terraform** provisions the infrastructure (VPC, Subnets, Security Groups, Load Balancer, and EC2/VM instances).
2. **`k8s.sh`** bootstraps Kubernetes inside the instances.

### AWS
- NLB handles `:6443` across 3 AZs.
- `ENVIRONMENT=aws` with AWS EBS CSI driver.

### GCP
- Internal TCP/UDP Load Balancer handles `:6443`.
- `ENVIRONMENT=gcp` with Compute Engine Persistent Disk CSI.

### Azure
- Azure Standard Load Balancer on port `:6443`.
- `ENVIRONMENT=azure` with Azure Disk CSI.

---

## 5. CKA Exam Scenarios

### Lab 1: etcd Backup & Restore with etcdctl
```bash
# 1. Snapshot
ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  snapshot save /var/lib/etcd-snapshot.db

# 2. Verify
ETCDCTL_API=3 etcdctl snapshot status /var/lib/etcd-snapshot.db

# 3. Restore
ETCDCTL_API=3 etcdctl snapshot restore /var/lib/etcd-snapshot.db \
  --data-dir=/var/lib/etcd-restored
```

### Lab 2: Upgrading Cluster with kubeadm
```bash
# Control plane upgrade
sudo apt-mark unhold kubeadm && sudo apt-get update && sudo apt-get install -y kubeadm=1.31.2-1.1
sudo apt-mark hold kubeadm
sudo kubeadm upgrade plan
sudo kubeadm upgrade apply v1.31.2

# Upgrade kubelet & kubectl
sudo apt-mark unhold kubelet kubectl && sudo apt-get install -y kubelet=1.31.2-1.1 kubectl=1.31.2-1.1
sudo apt-mark hold kubelet kubectl
sudo systemctl daemon-reload && sudo systemctl restart kubelet
```

### Lab 3: Troubleshooting a Broken Control Plane (Real Prod Issue)
**Scenario**: The Kubernetes API server is unresponsive (`kubectl` returns connection refused). This often happens in production if an admin makes a typo in a static pod manifest or if the container runtime crashes.
**Resolution**:
```bash
# 1. SSH into the affected control plane node (CP1)
ssh cp1

# 2. Since the API server is a static pod managed by kubelet, check kubelet logs
sudo journalctl -u kubelet -f
# Look for errors parsing the manifest or starting the container

# 3. Check for crashing API server containers using the CRI (containerd/crictl)
sudo crictl ps -a | grep kube-apiserver
sudo crictl logs <container-id>

# 4. Fix the misconfiguration in the static pod manifest
# Example: Correcting a typo like '--tls-cert-fiel' to '--tls-cert-file'
sudo vi /etc/kubernetes/manifests/kube-apiserver.yaml

# 5. Kubelet automatically detects the file change and restarts the static pod.
# Monitor the runtime until the API server container stays running:
watch 'sudo crictl ps | grep kube-apiserver'

# 6. Verify cluster access is restored
kubectl get nodes
```

### Lab 4: Troubleshooting Network Connectivity & NetworkPolicies (Cilium)
**Scenario**: A frontend pod is failing to communicate with a backend database pod. Both are running in the `prod` namespace, but the connection times out. This is a common production issue when rolling out zero-trust networking.
**Resolution**:
```bash
# 1. Verify the pod IPs and labels
kubectl get pods -n prod -o wide --show-labels
# Frontend IP: 10.0.1.15, Backend IP: 10.0.2.30

# 2. Test connectivity manually using a temporary pod (nslookup/curl)
kubectl exec -it <frontend-pod-name> -n prod -- curl -v http://10.0.2.30:3306
# Result: Connection Timed Out

# 3. Check for existing NetworkPolicies in the namespace
kubectl get networkpolicies -n prod
kubectl describe networkpolicy <policy-name> -n prod

# 4. Analyze the policy constraints
# Notice that the backend policy only allows ingress from pods with label 'role: web'
# But the frontend pod has label 'role: frontend'.

# 5. Fix the NetworkPolicy manifest or update the pod label
# Option A: Update the pod label to match the policy
kubectl label pod <frontend-pod-name> -n prod role=web --overwrite

# Option B: Edit the NetworkPolicy to allow 'role: frontend'
kubectl edit networkpolicy <policy-name> -n prod

# 6. Verify connectivity is restored
kubectl exec -it <frontend-pod-name> -n prod -- curl -v http://10.0.2.30:3306
# Result: Connection Successful (or valid HTTP response)
```
