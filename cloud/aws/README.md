# AWS Elastic Kubernetes Service (EKS): Architecture & Production Blueprint

This guide provides an enterprise architectural blueprint for running production workloads on **AWS EKS**, covering **AWS VPC CNI**, **AWS Load Balancer Controller**, **IAM Roles for Service Accounts (IRSA)**, **Karpenter Autoscaling**, and **EBS/EFS CSI storage**.

---

## 1. AWS EKS Core Architecture

```text
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                                  AWS EKS ARCHITECTURE                                  │
├────────────────────────────────────────────────────────────────────────────────────────┤
│ AWS Cloud Control Plane (Managed by AWS, Multi-AZ etcd & API Server across 3 AZs)      │
│                                           │                                            │
│                 ┌─────────────────────────┴─────────────────────────┐                  │
│                 ▼ (Private VPC Endpoint)                            ▼                  │
│   [ Compute Tier 1: Karpenter Nodes ]                 [ Compute Tier 2: Fargate ]      │
│   • On-Demand & Spot EC2 instances                    • Serverless, isolated microVMs  │
│   • Auto-provisioned in < 45 seconds                  • Ideal for batch/untrusted apps │
│   • AWS VPC CNI with Prefix Delegation                • Zero node management           │
│                                           │                                            │
│                 ┌─────────────────────────┴─────────────────────────┐                  │
│                 ▼                                                   ▼                  │
│   [ Storage: AWS EBS / EFS CSI ]                      [ Ingress: AWS LB Controller ]   │
│   • GP3 with custom IOPS & Throughput                 • Application Load Balancer (ALB)│
│   • EFS ReadWriteMany shared volume                   • Target-type: IP (Direct Pod)   │
└────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Core AWS EKS Add-ons & Integrations

### 1. AWS VPC CNI (`amazon-vpc-cni-k8s`)
- Assigns direct, routable private IP addresses from your AWS VPC subnet directly to each Pod.
- **Prefix Delegation (`ENABLE_PREFIX_DELEGATION=true`)**:
  - Without prefix delegation, a `c5.large` instance is limited to 29 pods due to EC2 ENI limits.
  - With prefix delegation (/28 IPv4 prefixes), a `c5.large` can run up to **110 pods**, maximizing compute density.
- **Security Groups for Pods**: Assigns native AWS Security Groups directly to Kubernetes Pods, enabling micro-segmentation at the pod level without complex NetworkPolicies.

### 2. AWS Load Balancer Controller (ALB & NLB)
- Manages AWS Application Load Balancers (Layer 7 Ingress) and Network Load Balancers (Layer 4 Service).
- **Target-Type: IP**: Instead of routing through NodePort hops, the ALB routes directly to the Pod's VPC IP address, eliminating double-hop latency and preserving client IP.

### 3. IAM Roles for Service Accounts (IRSA) vs. EKS Pod Identity
- **IRSA (OIDC Federation)**: Annotates Kubernetes ServiceAccounts with an IAM Role ARN:
  ```yaml
  eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/s3-reader-role
  ```
  The pod automatically receives temporary AWS STS credentials (`AWS_WEB_IDENTITY_TOKEN_FILE`), eliminating hardcoded AWS access keys.
- **EKS Pod Identity (New in 2024)**: Directly binds IAM roles to ServiceAccounts without requiring an OIDC provider or managing complex IAM trust policies.

### 4. Karpenter: Just-in-Time Autoscaling
- Replaces legacy Kubernetes Cluster Autoscaler.
- Directly calls the AWS **EC2 Fleet API**, evaluating un-schedulable pod resource requirements and spinning up the most cost-effective instance family (Graviton ARM, x86, Spot) in **under 45 seconds**.
- Continuous **Node Consolidation**: Automatically replaces fragmented or underutilized nodes with smaller or cheaper instances.

---

## 3. Production Manifests in this Module

| Manifest | Purpose |
| :--- | :--- |
| [01-aws-load-balancer-ingress.yaml](file:///Ubuntu/opt/myproject/kubernetes/cloud/aws/manifests/01-aws-load-balancer-ingress.yaml) | Internet-facing AWS ALB Ingress with ACM SSL/TLS certificate, target-type: IP, and SSL redirect |
| [02-irsa-serviceaccount.yaml](file:///Ubuntu/opt/myproject/kubernetes/cloud/aws/manifests/02-irsa-serviceaccount.yaml) | Kubernetes ServiceAccount bound to an AWS IAM Role via IRSA with S3 read permissions |
| [03-karpenter-nodepool.yaml](file:///Ubuntu/opt/myproject/kubernetes/cloud/aws/manifests/03-karpenter-nodepool.yaml) | Production Karpenter v1 `NodePool` & `EC2NodeClass` configuring Spot instance diversification |
| [04-ebs-gp3-storageclass.yaml](file:///Ubuntu/opt/myproject/kubernetes/cloud/aws/manifests/04-ebs-gp3-storageclass.yaml) | AWS EBS CSI `gp3` StorageClass with dynamic volume expansion, 3000 IOPS, and 125 MB/s throughput |
| [05-efs-rwx-storage.yaml](file:///Ubuntu/opt/myproject/kubernetes/cloud/aws/manifests/05-efs-rwx-storage.yaml) | AWS EFS CSI PersistentVolume and PVC providing `ReadWriteMany` shared network storage |
