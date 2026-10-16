# Unified Kubernetes & K3s Lab & Production Suite

A modular, enterprise-ready orchestration repository providing automated cluster bootstrap, configuration management, lifecycle tools, and advanced autoscaling for **Upstream Kubernetes (`kubeadm` + `containerd`)**, **Lightweight Kubernetes (`k3s`)**, and **Cloud-Native Serverless (`Knative` & `KEDA`)**.

---

## 1. Directory Structure

```text
kubernetes/
├── k8s/                           # Upstream Kubernetes (kubeadm / containerd) Suite
│   ├── k8s.sh                     # Unified CLI for upstream Kubernetes
│   ├── uninstall.sh               # Complete kubeadm reset & network cleanup
│   ├── config/
│   │   ├── cluster.env            # Global cluster settings (version, CIDRs, endpoint)
│   │   ├── control-plane.env      # Control plane settings (SANs, taints, advertise IP)
│   │   └── worker.env             # Worker node settings (labels, taints)
│   ├── scripts/                   # Modular installers (prereqs, containerd, packages, init, join, CNI, CSI)
│   ├── manifests/                 # HAProxy load balancer templates
│   ├── terraform/                 # Multi-cloud Terraform reference architectures (AWS, etc.)
│   ├── tests/
│   │   └── test_suite.sh          # 31 automated validation tests (All PASS)
│   └── README.md                  # Dedicated upstream Kubernetes documentation
│
├── k3s/                           # Lightweight K3s Suite
│   ├── k3s.sh                     # Unified CLI for K3s
│   ├── uninstall.sh               # K3s teardown, virtual link deletion & iptables cleanup
│   ├── config/
│   │   ├── cluster.env            # Global K3s settings (version, CNI, VIP, CIDRs)
│   │   ├── server.env             # Control plane settings (labels, taints, etcd snapshots)
│   │   └── worker.env             # Worker settings (labels, taints, extra flags)
│   ├── scripts/                   # Modular installers (prereqs, server, worker, CNI, MetalLB, Ingress)
│   ├── manifests/                 # HAProxy and MetalLB templates
│   ├── tests/
│   │   └── test_suite.sh          # 38 automated validation tests (All PASS)
│   └── README.md                  # Dedicated K3s documentation
│
├── serverless/                    # Cloud-Native Serverless & Event-Driven Autoscaling
│   ├── README.md                  # Master Knative vs. KEDA architecture comparison
│   ├── knative/                   # Knative Serving, Eventing, Scale-to-Zero & Kourier
│   │   ├── README.md              # Deep dive on KPA, Activator, Queue-Proxy, cold starts
│   │   ├── install-knative.sh     # Automated installer for Knative Serving + Kourier
│   │   └── manifests/             # 01-hello-service, 02-traffic-split, 03-eventing-ping
│   └── keda/                      # KEDA (Kubernetes Event-driven Autoscaling)
│       ├── README.md              # Deep dive on ScaledObject, ScaledJob, 60+ scalers
│       ├── install-keda.sh        # Automated installer for KEDA Operator & Metrics Server
│       └── manifests/             # 01-cron-scaler, 02-rabbitmq-queue, 03-redis-batch-job
│
├── monitoring/                    # Kubernetes Observability Manifests
│   ├── kubernetes-elk/            # Elasticsearch, Logstash, Kibana
│   ├── kubernetes-grafana/        # Grafana Dashboards & Datasources
│   └── kubernetes-prometheus/     # Prometheus Metrics & Alerting
│
├── namespace/                     # Namespace Quotas & Resource Management
│   ├── basic-resource-quota.yaml  # Memory & CPU quotas
│   └── deploy.yaml                # Sample application deployment
│
├── certificates/                  # Kubernetes Certificate Management & Renewal Suite
│   ├── README.md                  # Comprehensive PKI Architecture, Renewal & cert-manager guide
│   ├── scripts/
│   │   ├── check-certs.sh         # Automated cluster-wide expiration auditor (color-coded)
│   │   ├── renew-kubeadm-certs.sh # Safe automated renewal of control-plane PKI & kubeconfigs
│   │   └── rotate-k3s-certs.sh    # Automated rotation for K3s component certificates
│   └── manifests/
│       ├── install-cert-manager.sh # Automated cert-manager installer
│       ├── 01-clusterissuer-selfsigned.yaml # Internal CA & SelfSigned Issuer
│       ├── 02-clusterissuer-letsencrypt.yaml# Let's Encrypt ACME HTTP-01 & DNS-01 (Wildcard)
│       ├── 03-ingress-tls.yaml     # Production Ingress with automated TLS issuance
│       └── 04-vault-clusterissuer.yaml      # HashiCorp Vault PKI integration
│
├── cloud/                         # Enterprise Multi-Cloud Kubernetes Architecture (AWS, GCP, Azure)
│   ├── README.md                  # Master Multi-Cloud Architecture & Cross-Cloud Comparison Guide
│   ├── CLOUD_QA.md                # 45 In-Depth Multi-Cloud Questions & Answers
│   ├── aws/                       # Amazon Web Services (EKS) Suite
│   │   ├── README.md              # EKS Architecture, VPC CNI, IRSA, Karpenter, EBS/EFS CSI
│   │   └── manifests/             # 5 Production Manifests (ALB, IRSA, Karpenter, gp3, EFS RWX)
│   ├── gcp/                       # Google Cloud Platform (GKE) Suite
│   │   ├── README.md              # GKE Autopilot vs Standard, Datapath v2, Workload Identity, Gateway API
│   │   └── manifests/             # 5 Production Manifests (Gateway, Workload Identity, Regional PD, Filestore, Config Connector)
│   └── azure/                     # Microsoft Azure (AKS) Suite
│       ├── README.md              # AKS Architecture, Azure CNI Cilium, AGIC, Entra ID, Key Vault CSI
│       └── manifests/             # 5 Production Manifests (AGIC, Entra ID, Premium ZRS, Azure Files NFS, Key Vault)
│
├── BASIC_QA.md                    # 100 Core Kubernetes Fundamentals & CKA Questions & Answers
├── CKA_QA.md                      # Certified Kubernetes Administrator (CKA) 100 Practical Q&A + Workload Guide
├── CLOUD_QA.md                    # 45 In-Depth Multi-Cloud (AWS EKS, GCP GKE, Azure AKS) Questions & Answers
├── DEVOPS_ARCHITECT_QA.md         # 31 Deep-Dive DevOps Architect & Principal Platform Engineer Q&A
├── INTERVIEW_QA.md                # Senior/Lead Architect Interview Q&A (including Knative & KEDA)
├── LINUX_DEVOPS_QA.md             # 80 Practical Day-to-Day Linux Operations & Troubleshooting Q&A
└── README.md                      # This Master Guide
```

---

## 2. Architectural Comparison

```text
       Upstream Kubernetes (k8s/)                   Lightweight K3s (k3s/)
     ┌─────────────────────────────┐           ┌─────────────────────────────┐
     │  API LB / VIP (:6443)       │           │  API LB / VIP (:6443)       │
     └──────────────┬──────────────┘           └──────────────┬──────────────┘
                    │                                         │
        ┌───────────┼───────────┐                 ┌───────────┼───────────┐
        ▼           ▼           ▼                 ▼           ▼           ▼
     ┌─────┐     ┌─────┐     ┌─────┐           ┌─────┐     ┌─────┐     ┌─────┐
     │ CP1 │     │ CP2 │     │ CP3 │           │ CP1 │     │ CP2 │     │ CP3 │
     │etcd │     │etcd │     │etcd │           │etcd │     │etcd │     │etcd │
     └─────┘     └─────┘     └─────┘           └─────┘     └─────┘     └─────┘
        Static Pods (kube-apiserver,               Single binary process (k3s)
        kube-scheduler, controller)                with embedded etcd database
                    │                                         │
        ┌───────────┼───────────┐                 ┌───────────┼───────────┐
        ▼           ▼           ▼                 ▼           ▼           ▼
     ┌─────┐     ┌─────┐     ┌─────┐           ┌─────┐     ┌─────┐     ┌─────┐
     │ W1  │     │ W2  │     │ W3  │           │ W1  │     │ W2  │     │ W3  │
     └─────┘     └─────┘     └─────┘           └─────┘     └─────┘     └─────┘
     containerd CRI + Calico/Cilium            containerd CRI + Flannel/Calico
```

| Component | Upstream Kubernetes (`k8s/`) | K3s (`k3s/`) |
| :--- | :--- | :--- |
| **Bootstrapper** | `kubeadm` | Rancher `k3s.sh` script |
| **Container Runtime** | Dedicated `containerd` (`SystemdCgroup = true`) | Bundled `containerd` |
| **Control Plane** | Individual static pods (`/etc/kubernetes/manifests`) | Consolidated server process |
| **etcd Cluster** | Dedicated static pods + `etcdctl` | Embedded SQLite (single) or etcd (HA) |
| **Networking (CNI)** | Cilium default (or Calico) | Cilium default (or Flannel/Calico) |
| **Storage (CSI)** | Local-Path / Cloud CSI (AWS EBS, GCE PD, Azure Disk) | Local-Path provisioner built-in |
| **Autoscaling** | Standard HPA (CPU/RAM) | Standard HPA (CPU/RAM) |
| **Serverless / Events** | Knative & KEDA supported | Knative & KEDA supported |
| **Best Used For** | Enterprise production, **CKA Exam preparation** | Edge, IoT, local lab, WSL2, rapid CI/CD |
| **Test Suite** | 31 Automated Tests Passed | 38 Automated Tests Passed |

---

## 3. Quickstart Guides

### Option A: Deploy Upstream Kubernetes Cluster (`k8s/`)

```bash
cd /opt/myproject/kubernetes/k8s

# 1. On Load Balancer node (or CP1):
sudo ./k8s.sh lb 10.10.10.11 10.10.10.12 10.10.10.13

# 2. On Control Plane 1 (Bootstrap cluster):
sudo ROLE=control-plane \
     ENVIRONMENT=onprem \
     CONTROL_PLANE_ENDPOINT=k8s-api.lab.local \
     NODE_IP=10.10.10.11 \
     CNI=cilium \
     ./k8s.sh

# 3. Retrieve join tokens & certificate key:
sudo ./k8s.sh token

# 4. On Control Plane 2 & 3:
sudo ROLE=control-plane-join \
     CONTROL_PLANE_ENDPOINT=k8s-api.lab.local \
     NODE_IP=10.10.10.12 \
     JOIN_TOKEN="<TOKEN>" \
     DISCOVERY_TOKEN_CA_CERT_HASH="<HASH>" \
     CERTIFICATE_KEY="<CERT_KEY>" \
     ./k8s.sh

# 5. On Worker Nodes:
sudo ROLE=worker \
     CONTROL_PLANE_ENDPOINT=k8s-api.lab.local \
     JOIN_TOKEN="<TOKEN>" \
     DISCOVERY_TOKEN_CA_CERT_HASH="<HASH>" \
     ./k8s.sh

# 6. Check cluster diagnostics:
sudo ./k8s.sh health-check
```

---

### Option B: Deploy K3s Cluster (`k3s/`)

```bash
cd /opt/myproject/kubernetes/k3s

# 1. On Control Plane 1 (Initialize cluster):
sudo ROLE=server-init \
     NODE_IP=$(hostname -I | awk '{print $1}') \
     ./k3s.sh

# 2. Retrieve join token:
sudo ./k3s.sh token

# 3. On Control Plane 2 & 3:
sudo ROLE=server-join \
     NODE_IP=10.10.10.12 \
     K3S_URL=https://10.10.10.11:6443 \
     K3S_TOKEN="<TOKEN>" \
     ./k3s.sh

# 4. On Worker Nodes:
sudo ROLE=worker \
     K3S_URL=https://10.10.10.11:6443 \
     K3S_TOKEN="<TOKEN>" \
     ./k3s.sh

# 5. Check health:
sudo ./k3s.sh health-check
```

---

## 4. Serverless & Event-Driven Autoscaling (Knative & KEDA)

The `serverless/` suite addresses the limitations of standard Kubernetes HPA by introducing **Scale-to-Zero**, **HTTP Request Concurrency**, and **60+ Event Scalers**:

| Platform | Trigger Metric | Scale-to-Zero | Key Strengths |
| :--- | :--- | :--- | :--- |
| **Knative Serving** | HTTP Request Rate & Concurrency | ✅ Yes (0 ↔ N) | Built-in canary traffic splitting (80/20), revision snapshots, automatic Ingress routing, instant cold start activation via Activator. |
| **KEDA** | 60+ Event Sources (Queues, Kafka, DBs, Cron) | ✅ Yes (0 ↔ N) | Plugs directly into standard HPA via External Metrics API; scales long-running Deployments (`ScaledObject`) or ephemeral batch tasks (`ScaledJob`). |

- **Knative Module**: [serverless/knative/README.md](file:///Ubuntu/opt/myproject/kubernetes/serverless/knative/README.md)
- **KEDA Module**: [serverless/keda/README.md](file:///Ubuntu/opt/myproject/kubernetes/serverless/keda/README.md)
- **Architectural Comparison**: [serverless/README.md](file:///Ubuntu/opt/myproject/kubernetes/serverless/README.md)

---

## 5. Kubernetes Certificate Management & Renewal

The `certificates/` suite provides operational tools for managing, monitoring, and renewing both **control-plane internal certificates** and **application-layer public SSL/TLS certificates**:

```bash
# 1. Audit all certificate expiration dates across kubeadm, k3s, and kubeconfigs
sudo ./certificates/scripts/check-certs.sh

# 2. Safely renew kubeadm control plane certificates with automated backup
sudo ./certificates/scripts/renew-kubeadm-certs.sh

# 3. Rotate K3s component certificates on disk
sudo ./certificates/scripts/rotate-k3s-certs.sh
```

| Area | Scope | Tools & Mechanisms |
| :--- | :--- | :--- |
| **Control Plane PKI** | API server, etcd, controller-manager, scheduler | `kubeadm certs check-expiration`, `kubeadm certs renew all`, static pod restarts |
| **K3s Component TLS** | K3s server & agent internal certificates | `k3s certificate check`, `k3s certificate rotate` |
| **Kubelet TLS** | Node client & server certificates | Auto-rotated via CSR API (`certificates.k8s.io`), approved via `kubectl certificate approve` |
| **Ingress & Apps** | Public HTTPS & Internal mTLS | **cert-manager** with ACME HTTP-01 / DNS-01 (Let's Encrypt) and HashiCorp Vault PKI |

- **Complete Operations Guide**: [certificates/README.md](certificates/README.md)
- **Production Manifests**: [certificates/manifests/](certificates/manifests/)

---

## 6. Enterprise Multi-Cloud Kubernetes Suite (AWS, GCP, Azure)

The `cloud/` suite provides an end-to-end production architecture, deployment patterns, and validated manifests across the Big 3 public cloud managed Kubernetes services:

| Technical Dimension | AWS EKS (`cloud/aws/`) | GCP GKE (`cloud/gcp/`) | Azure AKS (`cloud/azure/`) |
| :--- | :--- | :--- | :--- |
| **Control Plane SLA** | 99.95% ($0.10/hr/cluster) | 99.95% (Autopilot free mgmt fee; Standard $0.10/hr) | 99.95% (Standard/Premium SLA; Free tier available) |
| **Primary CNI Engine** | AWS VPC CNI (Prefix Delegation) | GKE Datapath v2 (**Cilium eBPF**) | Azure CNI Overlay (**Powered by Cilium**) |
| **Pod IAM Authentication** | EKS Pod Identity / IRSA (OIDC) | Workload Identity Federation | Microsoft Entra Workload ID |
| **Ingress & L7 Gateway** | AWS Load Balancer Controller (ALB) | GKE Gateway API (Global Anycast) | Application Gateway Ingress Controller (AGIC) |
| **Autoscaling Engine** | **Karpenter** (Group-less, fast bin-pack) | Cluster Autoscaler + Node Auto-Provisioning | Karpenter on AKS / Node Auto-Provisioning |
| **Persistent Block Storage** | EBS CSI (`gp3`, `io2 Block Express`) | GCE Persistent Disk (Regional Balanced PD) | Azure Disk CSI (Premium SSD v2, Ultra Disk) |
| **Shared File Storage (RWX)**| EFS CSI (NFS v4.1) / FSx for Lustre | Filestore CSI / Cloud Storage FUSE | Azure Files CSI (NFS v4.1 / SMB) |
| **Cloud Secrets Integration**| External Secrets Operator / AWS Secrets | Cloud Secret Manager + Workload Identity | Azure Key Vault Provider for Secrets Store CSI |

- **Master Multi-Cloud Architecture Guide**: [cloud/README.md](cloud/README.md)
- **Multi-Cloud Q&A Guide (45 Questions & Answers)**: [CLOUD_QA.md](CLOUD_QA.md) / [cloud/CLOUD_QA.md](cloud/CLOUD_QA.md)
- **AWS EKS Guide & Manifests**: [cloud/aws/README.md](cloud/aws/README.md)
- **GCP GKE Guide & Manifests**: [cloud/gcp/README.md](cloud/gcp/README.md)
- **Azure AKS Guide & Manifests**: [cloud/azure/README.md](cloud/azure/README.md)

---

## 7. Certified Kubernetes Administrator (CKA) Exam Labs

### Lab 1: etcd Snapshot Backup & Restoration
- **In `k8s/` (Using `etcdctl`)**:
  ```bash
  ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key \
    snapshot save /var/lib/etcd-backup.db
  ```
- **In `k3s/` (Using native snapshot tool)**:
  ```bash
  sudo k3s etcd-snapshot save --name cka-backup-01
  sudo k3s etcd-snapshot list
  ```

### Lab 2: Safe Node Maintenance (Drain / Cordon)
```bash
# Cordon node to stop scheduling new pods
kubectl cordon <node-name>

# Evict existing pods safely
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data

# Perform maintenance or upgrades, then uncordon
kubectl uncordon <node-name>
```

### Lab 3: Zero-Downtime Cluster Version Upgrades
- In `k8s/`:
  ```bash
  sudo apt-mark unhold kubeadm && sudo apt-get update && sudo apt-get install -y kubeadm=1.31.2-1.1
  sudo kubeadm upgrade plan
  sudo kubeadm upgrade apply v1.31.2
  sudo apt-mark unhold kubelet kubectl && sudo apt-get install -y kubelet=1.31.2-1.1 kubectl=1.31.2-1.1
  sudo systemctl daemon-reload && sudo systemctl restart kubelet
  ```
- In `k3s/`:
  Update `K3S_VERSION` in `config/cluster.env` and re-run `./k3s.sh server-init` across nodes sequentially.

---

## 8. CKA Preparation Roadmap

| Phase | Topics | Priority |
| :---: | :--- | :--- |
| 1 | Kubernetes Architecture & Core Concepts | ★★★★★ |
| 2 | Pods, Deployments, ReplicaSets | ★★★★★ |
| 3 | Services & Networking | ★★★★★ |
| 4 | ConfigMaps & Secrets | ★★★★☆ |
| 5 | Storage, PV, PVC, StorageClass | ★★★★★ |
| 6 | Scheduling, Taints, Tolerations, Affinity | ★★★★★ |
| 7 | RBAC & Security | ★★★★★ |
| 8 | Ingress & Gateway concepts | ★★★★☆ |
| 9 | Helm & Application Management | ★★★☆☆ |
| 10 | Troubleshooting | ★★★★★ |
| 11 | Cluster Maintenance & Upgrades | ★★★★★ |
| 12 | ETCD backup/restore | ★★★★★ |
| 13 | Advanced kubectl | ★★★★★ |
| 14 | Full CKA Mock Exams | ★★★★★ |

---

## 9. Automated Verification Test Suites

Both suites include comprehensive automated testing with mock execution, syntax validation, and flag assembly checks:

```bash
# Test Upstream Kubernetes suite (31 tests)
/opt/myproject/kubernetes/k8s/tests/test_suite.sh

# Test K3s suite (38 tests)
/opt/myproject/kubernetes/k3s/tests/test_suite.sh
```

**Total Test Coverage: 69/69 Tests Passing (100% Pass Rate)**
