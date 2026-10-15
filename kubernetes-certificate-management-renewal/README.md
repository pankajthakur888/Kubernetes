# Kubernetes Certificate Management & Renewal: The Complete Operations Guide

This guide covers the entire lifecycle of **Kubernetes PKI certificates**, including the **Control Plane internal certificates** (`kubeadm`, `k3s`, `etcd`, `kubelet`), **automated and manual certificate renewal**, **disaster recovery when certificates have already expired**, and **application-layer TLS automation using `cert-manager`**.

---

## 1. Kubernetes PKI Architecture & Certificate Inventory

A production Kubernetes cluster uses multiple independent Certificate Authorities (CAs) and certificates to secure inter-component communication:

```text
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                              KUBERNETES PKI ARCHITECTURE                               │
├────────────────────────────────────────────────────────────────────────────────────────┤
│ 1. Kubernetes Main Root CA (/etc/kubernetes/pki/ca.crt)                                │
│    ├── API Server Serving Certificate (apiserver.crt)                                  │
│    ├── API Server Kubelet Client (apiserver-kubelet-client.crt)                        │
│    ├── Kubelet Client Certificate (kubelet.conf client-certificate-data)               │
│    ├── Controller Manager Client (controller-manager.conf client-certificate-data)     │
│    └── Scheduler Client (scheduler.conf client-certificate-data)                       │
│                                                                                        │
│ 2. Front-Proxy CA (/etc/kubernetes/pki/front-proxy-ca.crt)                             │
│    └── Front-Proxy Client (front-proxy-client.crt) - For API aggregation & metrics     │
│                                                                                        │
│ 3. etcd CA (/etc/kubernetes/pki/etcd/ca.crt)                                           │
│    ├── etcd Server Certificate (etcd/server.crt)                                       │
│    ├── etcd Peer Certificate (etcd/peer.crt)                                           │
│    ├── API Server etcd Client (apiserver-etcd-client.crt)                              │
│    └── etcd Healthcheck Client (etcd/healthcheck-client.crt)                           │
│                                                                                        │
│ 4. Service Account Key Pair (/etc/kubernetes/pki/sa.key, sa.pub)                       │
│    └── Asymmetric RSA keys used to sign and verify ServiceAccount JWT tokens           │
└────────────────────────────────────────────────────────────────────────────────────────┘
```

### Complete Certificate Inventory Table (Default kubeadm)

| Certificate File | Common Name (CN) | Subject Alternative Names (SANs) | Validity | Issuer CA |
| :--- | :--- | :--- | :--- | :--- |
| `pki/ca.crt` | `kubernetes` | — | 10 Years | Self-Signed Root CA |
| `pki/apiserver.crt` | `kube-apiserver` | `<NodeIP>`, `10.96.0.1`, `kubernetes`, `kubernetes.default`, `localhost`, `k8s-api` | 1 Year | `pki/ca.crt` |
| `pki/apiserver-kubelet-client.crt` | `kube-apiserver-kubelet-client` | `system:masters` group | 1 Year | `pki/ca.crt` |
| `pki/front-proxy-ca.crt` | `front-proxy-ca` | — | 10 Years | Self-Signed Front-Proxy CA |
| `pki/front-proxy-client.crt` | `front-proxy-client` | — | 1 Year | `pki/front-proxy-ca.crt` |
| `pki/etcd/ca.crt` | `etcd-ca` | — | 10 Years | Self-Signed etcd CA |
| `pki/etcd/server.crt` | `<node-name>` | `<NodeIP>`, `127.0.0.1`, `localhost` | 1 Year | `pki/etcd/ca.crt` |
| `pki/etcd/peer.crt` | `<node-name>` | `<NodeIP>`, `127.0.0.1`, `localhost` | 1 Year | `pki/etcd/ca.crt` |
| `pki/apiserver-etcd-client.crt` | `kube-apiserver-etcd-client` | `system:masters` group | 1 Year | `pki/etcd/ca.crt` |
| `admin.conf` | `kubernetes-admin` | `system:masters` group | 1 Year | `pki/ca.crt` |
| `kubelet.conf` | `system:node:<node-name>` | `system:nodes` group | 1 Year (auto-rotated) | `pki/ca.crt` |

> [!IMPORTANT]
> The **Root CAs (`ca.crt`, `etcd/ca.crt`, `front-proxy-ca.crt`) are valid for 10 years**, but **all component client/server certificates expire after exactly 1 year (365 days)**!

---

## 2. Proactive Monitoring & Expiration Detection

### Method A: Using kubeadm Native Checker (Recommended)
```bash
sudo kubeadm certs check-expiration
```
*Sample Output:*
```text
CERTIFICATE                EXPIRES                  RESIDUAL TIME   CERTIFICATE AUTHORITY   EXTERNALLY MANAGED
admin.conf                 Oct 15, 2027 10:00 UTC   364d            ca                      no
apiserver                  Oct 15, 2027 10:00 UTC   364d            ca                      no
apiserver-etcd-client      Oct 15, 2027 10:00 UTC   364d            etcd-ca                 no
apiserver-kubelet-client   Oct 15, 2027 10:00 UTC   364d            ca                      no
controller-manager.conf    Oct 15, 2027 10:00 UTC   364d            ca                      no
etcd-healthcheck-client    Oct 15, 2027 10:00 UTC   364d            etcd-ca                 no
etcd-peer                  Oct 15, 2027 10:00 UTC   364d            etcd-ca                 no
etcd-server                Oct 15, 2027 10:00 UTC   364d            etcd-ca                 no
front-proxy-client         Oct 15, 2027 10:00 UTC   364d            front-proxy-ca          no
scheduler.conf             Oct 15, 2027 10:00 UTC   364d            ca                      no
```

### Method B: Using OpenSSL (For any single certificate)
```bash
# Check exact expiration date
sudo openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -enddate

# Check Subject, Issuer, and SANs
sudo openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -subject -issuer -ext subjectAltName

# Check embedded client certificate inside a kubeconfig file
grep "client-certificate-data" /etc/kubernetes/admin.conf | awk '{print $2}' | base64 -d | openssl x509 -noout -enddate
```

### Method C: Checking K3s Certificates
In K3s, certificates are located at `/var/lib/rancher/k3s/server/tls`:
```bash
sudo k3s certificate check
```

### Method D: Automated Cluster-Wide Audit Script
Run the included auditing script in this directory:
```bash
sudo ./scripts/check-certs.sh
```

---

## 3. Routine Certificate Renewal Procedures

### 1. Automated Renewal via Cluster Upgrade (Best Practice)
When you upgrade your cluster using `kubeadm upgrade apply v1.x.y`, **kubeadm automatically renews all control plane certificates** that expire within the next 180 days!
If you follow the recommended practice of upgrading Kubernetes minor versions every 4 to 8 months, your certificates will never expire.

---

### 2. Manual Renewal on Upstream Kubernetes (`kubeadm`)
If you are not upgrading the cluster, renew certificates manually before the 1-year mark:

#### Step 1: Backup Existing Certificates & Kubeconfigs (Critical!)
```bash
sudo cp -r /etc/kubernetes/pki /etc/kubernetes/pki.backup.$(date +%F)
sudo cp /etc/kubernetes/*.conf /tmp/
```

#### Step 2: Renew All Certificates
```bash
# Renew all control-plane certificates and kubeconfig files
sudo kubeadm certs renew all
```
*Or renew individual certificates:*
```bash
sudo kubeadm certs renew apiserver
sudo kubeadm certs renew apiserver-kubelet-client
sudo kubeadm certs renew admin.conf
```

#### Step 3: Update User Kubeconfig
The renewal updates `/etc/kubernetes/admin.conf`. Copy the updated certificate to your user directory:
```bash
sudo cp -f /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

#### Step 4: Restart Control Plane Static Pods
The static pods (`kube-apiserver`, `kube-controller-manager`, `kube-scheduler`, and `etcd`) load their certificates into memory **only at boot time**. They must be restarted to load the newly renewed certificates.

*Method A: Move manifests temporarily (Triggers Kubelet pod recreate)*
```bash
sudo mv /etc/kubernetes/manifests/*.yaml /tmp/
# Wait 10 seconds for Kubelet to terminate the static pods
sleep 10
sudo mv /tmp/*.yaml /etc/kubernetes/manifests/
```

*Method B: Restart Container Runtime*
```bash
sudo systemctl restart containerd
```

#### Step 5: Verify Cluster Health
```bash
kubectl get nodes
kubectl get pods -n kube-system
sudo kubeadm certs check-expiration
```

---

### 3. Manual Certificate Rotation on K3s
K3s automatically renews certificates on restart if they expire within 90 days. To force manual rotation immediately:

```bash
# 1. Stop K3s server
sudo systemctl stop k3s

# 2. Rotate all component certificates on disk
sudo k3s certificate rotate

# 3. Start K3s server
sudo systemctl start k3s

# 4. Verify updated expiration dates
sudo k3s certificate check
```

---

## 4. Kubelet Certificate Auto-Rotation & CSR Management

Unlike the control plane, worker node `kubelet` instances manage client certificates via the Kubernetes **Certificates API** (`certificates.k8s.io`).

### 1. Kubelet Client Certificate Auto-Rotation
In modern Kubernetes, `RotateKubeletClientCertificate: true` is enabled by default:
1. When the Kubelet client certificate reaches ~70% of its lifetime, Kubelet automatically generates a private key and submits a **CertificateSigningRequest (CSR)** to the API server.
2. The `kube-controller-manager` automatically approves the client CSR and issues a new certificate stored in `/var/lib/kubelet/pki/kubelet-client-current.pem`.

### 2. Kubelet Server Certificate Rotation & Approval
For `kubelet` server certificates (used by `kubectl logs` and `kubectl exec` to connect to port 10250), auto-approval is disabled by default for security.

To enable Kubelet server certificate rotation:
```yaml
# In /var/lib/kubelet/config.yaml
serverTLSBootstrap: true
```
When Kubelet submits a server certificate CSR, it remains in `Pending` state until approved:
```bash
# 1. View pending CSRs
kubectl get csr

# 2. Approve the pending Kubelet server CSR
kubectl certificate approve <csr-name>
```

---

## 5. Emergency Disaster Recovery: When Certificates Have Already Expired

When certificates expire, `kubectl` stops working and throws the dreaded error:
```text
Unable to connect to the server: x509: certificate has expired or is not yet valid
```
Because the API server certificate is expired, you cannot use `kubectl` to fix it. Follow this emergency recovery procedure:

### Emergency Step-by-Step Recovery:

#### Step 1: Temporarily Roll Back System Time (If Needed)
If `kubeadm certs renew` fails to communicate, temporarily roll back system clock by 3 days:
```bash
sudo timedatectl set-ntp false
sudo date -s "3 days ago"
```

#### Step 2: Backup Existing PKI
```bash
sudo cp -r /etc/kubernetes /etc/kubernetes.expired.backup
```

#### Step 3: Force Re-generation of Certificates
```bash
# Renew all certificates unconditionally
sudo kubeadm certs renew all
```

#### Step 4: Re-generate Administrative Kubeconfigs
```bash
sudo kubeadm init phase kubeconfig all
```

#### Step 5: Restore System Clock & Restart Kubelet
```bash
sudo timedatectl set-ntp true
sudo systemctl daemon-reload
sudo systemctl restart kubelet
sudo systemctl restart containerd
```

#### Step 6: Update User Kubeconfig
```bash
sudo cp -f /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

#### Step 7: Verify Access
```bash
kubectl get nodes
```

---

## 6. Application Ingress TLS with cert-manager

While internal cluster PKI secures Kubernetes control plane traffic, **cert-manager** is the CNCF standard for automating **public SSL/TLS certificates** for applications, microservices, and Ingress controllers.

```text
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                               CERT-MANAGER ARCHITECTURE                                │
├────────────────────────────────────────────────────────────────────────────────────────┤
│ [ Ingress Resource ] (Annotation: cert-manager.io/cluster-issuer: letsencrypt-prod)   │
│         │                                                                              │
│         ▼                                                                              │
│ [ Certificate CRD ] ──► Creates ──► [ CertificateRequest ] ──► [ Order & Challenge ]   │
│                                                                        │               │
│                        ACME Protocol Validation                        ▼               │
│                 (HTTP-01 Ingress / DNS-01 Cloudflare/Route53) ◄──► [ Let's Encrypt ]   │
│                                                                        │               │
│                                   Issues Valid TLS                     ▼               │
│ [ Kubernetes Secret (tls.crt, tls.key) ] ◄─────────────────────────────┘               │
│         │                                                                              │
│         ▼ Automatically reloaded by Ingress / Envoy Proxy                              │
│ [ External Client (HTTPS Browser) ]                                                    │
└────────────────────────────────────────────────────────────────────────────────────────┘
```

### 1. Automated Installation
Install cert-manager v1.15+ with native CRDs:
```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.15.3/cert-manager.yaml
```

### 2. ACME Challenge Types: HTTP-01 vs. DNS-01

| Feature | ACME HTTP-01 Challenge | ACME DNS-01 Challenge |
| :--- | :--- | :--- |
| **How It Works** | Proves ownership by placing a temporary file on an HTTP endpoint (`/.well-known/acme-challenge/`) | Proves ownership by creating a temporary `_acme-challenge` TXT record in your DNS provider |
| **Port Requirements** | Port 80 must be open and routed to the cluster from the public internet | No inbound ports required; works in private/air-gapped networks |
| **Wildcard Support** | ❌ No (cannot issue `*.example.com`) | ✅ Yes (supports wildcard certificates) |
| **Supported Providers** | Any Ingress controller (NGINX, Traefik, Contour) | Cloudflare, AWS Route53, Google Cloud DNS, Azure DNS |

---

### 3. Production Manifests in this Module

| Manifest | Purpose |
| :--- | :--- |
| [01-clusterissuer-selfsigned.yaml](file:///Ubuntu/opt/myproject/kubernetes/kubernetes-certificate-management-renewal/manifests/01-clusterissuer-selfsigned.yaml) | Self-Signed & Internal Root CA ClusterIssuer for internal dev/testing and mTLS |
| [02-clusterissuer-letsencrypt.yaml](file:///Ubuntu/opt/myproject/kubernetes/kubernetes-certificate-management-renewal/manifests/02-clusterissuer-letsencrypt.yaml) | Let's Encrypt Staging and Production ClusterIssuers (HTTP-01 & DNS-01) |
| [03-ingress-tls.yaml](file:///Ubuntu/opt/myproject/kubernetes/kubernetes-certificate-management-renewal/manifests/03-ingress-tls.yaml) | Production Ingress manifest with automatic Let's Encrypt TLS certificate generation |
| [04-vault-clusterissuer.yaml](file:///Ubuntu/opt/myproject/kubernetes/kubernetes-certificate-management-renewal/manifests/04-vault-clusterissuer.yaml) | HashiCorp Vault PKI Engine integration for zero-trust enterprise certificate issuance |

---

## 7. Operational Scripts

This module includes automated operations scripts in the `scripts/` directory:

1. **[`scripts/check-certs.sh`](file:///Ubuntu/opt/myproject/kubernetes/kubernetes-certificate-management-renewal/scripts/check-certs.sh)**:
   Scans `/etc/kubernetes/pki`, `/var/lib/rancher/k3s/server/tls`, all `.conf` kubeconfigs, and `cert-manager` certificates. Color-codes results and flags any certificate expiring within 30 days.
2. **[`scripts/renew-kubeadm-certs.sh`](file:///Ubuntu/opt/myproject/kubernetes/kubernetes-certificate-management-renewal/scripts/renew-kubeadm-certs.sh)**:
   Safely creates a timestamped backup, renews all control-plane certificates, updates `admin.conf`, and restarts static pods.
3. **[`scripts/rotate-k3s-certs.sh`](file:///Ubuntu/opt/myproject/kubernetes/kubernetes-certificate-management-renewal/scripts/rotate-k3s-certs.sh)**:
   Rotates K3s TLS certificates safely and restarts the k3s server.
