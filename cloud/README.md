# Multi-Cloud Kubernetes Architecture: AWS (EKS) vs. GCP (GKE) vs. Azure (AKS)

This guide provides an enterprise-grade architectural comparison, implementation blueprints, and service mappings across the three major hyperscale cloud Kubernetes providers: **Amazon Web Services (AWS EKS)**, **Google Cloud Platform (GCP GKE)**, and **Microsoft Azure (AKS)**.

---

## 1. Executive Multi-Cloud Comparison Matrix

```text
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                        ENTERPRISE MULTI-CLOUD MATRIX                                   │
├─────────────────────┬──────────────────────────┬───────────────────────┬───────────────┤
│ Architecture Layer  │ AWS EKS                  │ GCP GKE               │ Azure AKS     │
├─────────────────────┼──────────────────────────┼───────────────────────┼───────────────┤
│ Control Plane SLA   │ 99.95% ($0.10/hr)        │ 99.95% ($0.10/hr)     │ 99.95% ($0.10)│
│ Default CNI         │ AWS VPC CNI (Direct ENI) │ Datapath v2 (Cilium)  │ Azure CNI     │
│ Cloud Ingress / L7  │ AWS Load Balancer (ALB)  │ Gateway API / GKE Ingr│ AGIC (AppGW)  │
│ Workload IAM        │ IRSA / Pod Identity      │ Workload Identity     │ Entra Workload│
│ Block Storage (CSI) │ EBS CSI (GP3 / io2)      │ GCE PD CSI (Balanced) │ Azure Disk CSI│
│ Shared File (RWX)   │ EFS CSI (NFS)            │ Filestore CSI (NFS)   │ Azure Files   │
│ Autoscaling Engine  │ Karpenter (EC2 Fleet)    │ Node Auto-Provisioning│ Virtual Nodes │
│ Cloud Secrets       │ AWS Secrets Manager      │ GCP Secret Manager    │ Azure KeyVault│
│ Observability       │ CloudWatch / ADOT        │ Managed Prometheus GMP│ Azure Monitor │
│ K8s As Infrastructure│ ACK (AWS Controller)    │ Config Connector      │ ASO (Operator)│
└─────────────────────┴──────────────────────────┴───────────────────────┴───────────────┘
```

---

## 2. Deep-Dive Architectural Service Comparison

### A. Networking & Container Network Interface (CNI)

| Cloud Provider | CNI Architecture | How Pod IPs are Allocated | Key Performance & Limit Considerations |
| :--- | :--- | :--- | :--- |
| **AWS EKS** | **AWS VPC CNI** (`amazon-vpc-cni-k8s`) | Pods get direct routable secondary private IPs from the node's AWS VPC subnet. | • Subject to EC2 instance type ENI/IP limits.<br>• Requires **Prefix Delegation** (`ENABLE_PREFIX_DELEGATION=true`) to run dense pods.<br>• Supports **Security Groups for Pods** (`aws-k8s-cni`). |
| **GCP GKE** | **GKE Datapath v2** (eBPF / Cilium) | Uses native VPC-native Alias IP ranges. Pod CIDRs are allocated from secondary subnet ranges. | • **eBPF-native**: Bypasses `kube-proxy` iptables completely.<br>• In-kernel packet routing and native network policy enforcement.<br>• Zero encapsulation overhead. |
| **Azure AKS** | **Azure CNI Powered by Cilium** (or Overlay) | Direct VNet private IPs (Legacy) or Overlay mode (POD CIDR decoupled from VNet). | • Legacy Azure CNI consumes huge VNet IP spaces.<br>• **Azure CNI Overlay** + Cilium is the recommended standard: scalable IP allocation with eBPF high-speed data path. |

---

### B. Identity & Access Management (Workload Identity)

Never store static cloud API keys or IAM secrets inside Kubernetes pods! All three clouds support **OIDC-based federated workload identity**:

```text
AWS:   Pod ServiceAccount ──(OIDC Role ARN)──► AWS STS ───────► Temporary IAM Credentials
GCP:   Pod ServiceAccount ──(GSA Annotation)─► Google STS ────► Temporary OAuth Access Token
Azure: Pod ServiceAccount ──(Client-ID)──────► Entra ID (OIDC)► Short-lived Azure Bearer Token
```

- **AWS EKS:** **IRSA (IAM Roles for Service Accounts)** & **EKS Pod Identity**. Maps Kubernetes ServiceAccount annotations to AWS IAM Roles via AWS STS AssumeRoleWithWebIdentity.
- **GCP GKE:** **Workload Identity**. Binds Kubernetes ServiceAccount to a Google Cloud IAM Service Account (GSA) with `roles/iam.workloadIdentityUser`.
- **Azure AKS:** **Microsoft Entra Workload ID**. Replaces legacy Pod Identity; uses OpenID Connect federation between the AKS cluster OIDC issuer and Microsoft Entra ID.

---

### C. Node Autoscaling: Karpenter vs. NAP vs. Virtual Nodes

```text
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                              CLOUD AUTOSCALING COMPARISON                              │
├────────────────────────────────────────────────────────────────────────────────────────┤
│ AWS EKS: Karpenter                                                                     │
│ • Bypasses Auto Scaling Groups (ASGs). Directly calls EC2 Fleet API.                   │
│ • Selects exact instance family (c6i, m6i, r6i, Spot) matching pod requests in < 45s.  │
│ • Active bin-packing and continuous node consolidation downsizes/defrags clusters.     │
│                                                                                        │
│ GCP GKE: Node Auto-Provisioning (NAP) & Autopilot                                      │
│ • Automatically creates new node pools of right-sized machine types on demand.         │
│ • GKE Autopilot mode fully abstracts worker nodes: you only pay for pod CPU/RAM!       │
│                                                                                        │
│ Azure AKS: Virtual Nodes (Azure Container Instances - ACI) & Karpenter AKS            │
│ • Bursts traffic into serverless Azure Container Instances (ACI) without VM provisioning.│
│ • Native Karpenter support on AKS enables sub-minute EC2-like VM provisioning.         │
└────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Directory Layout & Module Index

```text
cloud/
├── README.md                      # This master multi-cloud architecture guide
│
├── aws/                           # Amazon Web Services (EKS) Suite
│   ├── README.md                  # EKS architecture, VPC CNI, IRSA, Karpenter guide
│   └── manifests/
│       ├── 01-aws-load-balancer-ingress.yaml # Application Load Balancer (ALB) Ingress
│       ├── 02-irsa-serviceaccount.yaml       # IAM Roles for Service Accounts (IRSA)
│       ├── 03-karpenter-nodepool.yaml        # Karpenter NodePool & EC2NodeClass (Spot/On-Demand)
│       ├── 04-ebs-gp3-storageclass.yaml      # EBS CSI GP3 dynamic storage with IOPS tuning
│       └── 05-efs-rwx-storage.yaml           # AWS EFS ReadWriteMany shared filesystem
│
├── gcp/                           # Google Cloud Platform (GKE) Suite
│   ├── README.md                  # GKE Autopilot/Standard, Datapath v2, Gateway API guide
│   └── manifests/
│       ├── 01-gke-gateway-api.yaml           # GKE Gateway API HTTPRoute & Gateway
│       ├── 02-workload-identity.yaml         # Google Cloud Workload Identity binding
│       ├── 03-gce-pd-storageclass.yaml       # Regional Persistent Disk CSI (HA cross-zone)
│       ├── 04-filestore-nfs-pvc.yaml         # Google Cloud Filestore ReadWriteMany storage
│       └── 05-config-connector.yaml          # GCP resources as K8s CRDs (Cloud SQL / PubSub)
│
└── azure/                         # Microsoft Azure (AKS) Suite
    ├── README.md                  # AKS architecture, Azure CNI Cilium, AGIC, Workload ID
    └── manifests/
        ├── 01-agic-ingress.yaml              # Azure Application Gateway Ingress Controller (AGIC)
        ├── 02-entra-workload-id.yaml         # Microsoft Entra Workload Identity federated credential
        ├── 03-azure-disk-storageclass.yaml   # Azure Managed Premium SSD v2 StorageClass
        ├── 04-azure-files-rwx.yaml           # Azure Files CSI ReadWriteMany storage
        └── 05-keyvault-secretprovider.yaml   # Azure Key Vault Secrets Store CSI Driver
```

---

## 4. Multi-Cloud Migration & Strategy

When architecting for multi-cloud or migrating between providers:
1. **Abstract Ingress via Gateway API:** Standardize on the Kubernetes **Gateway API** (`gateway.networking.k8s.io`) rather than proprietary ingress annotations.
2. **Abstract Identity via OIDC / SPIFFE:** Use unified OIDC ServiceAccounts or SPIRE rather than cloud-specific IAM SDKs in your code.
3. **Decouple Storage:** For multi-cloud portability, run distributed software-defined storage (Rook-Ceph / Portworx) or use cloud-agnostic S3-compatible object storage.
4. **GitOps as the Single Pane of Glass:** Use **ArgoCD** deployed in a hub management cluster to synchronize identical workloads across AWS EKS, GCP GKE, and Azure AKS.
