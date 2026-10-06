# Modular K3s Lab & Production Cluster Suite

A reusable, enterprise-grade K3s orchestration suite tailored for Kubernetes operators, DevOps engineers, and **Certified Kubernetes Administrator (CKA)** exam preparation.

---

## 1. Architecture Overview

### High Availability (HA) Control Plane with Embedded etcd

In an embedded etcd topology, **3 control plane nodes** are required for quorum ($N=3$, fault tolerance = $1$). Having only 2 control plane nodes is fragile: if either node fails, the cluster loses quorum and cannot process writes.

```text
                           Internet / Clients
                                   │
                                   ▼
                    ┌──────────────────────────────┐
                    │      HA API Load Balancer    │
                    │   (HAProxy / VIP :6443)      │
                    └──────────────┬───────────────┘
                                   │
            ┌──────────────────────┼──────────────────────┐
            │                      │                      │
            ▼                      ▼                      ▼
     ┌─────────────┐        ┌─────────────┐        ┌─────────────┐
     │     CP1     │◄──────►│     CP2     │◄──────►│     CP3     │
     │  (etcd 1)   │        │  (etcd 2)   │        │  (etcd 3)   │
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
```

---

## 2. Directory Layout

```text
k3s/
├── k3s.sh                         # Unified master CLI & orchestrator
├── uninstall.sh                   # Cluster teardown & network interface cleanup
├── config/
│   ├── cluster.env                # Global cluster settings (version, VIP, CIDR, CNI)
│   ├── server.env                 # Control-plane settings (labels, taints, etcd backups)
│   └── worker.env                 # Worker settings (labels, taints, kubelet args)
├── scripts/
│   ├── common.sh                  # Shared logging, OS detection, IP discovery
│   ├── install.sh                 # Host prerequisites, sysctl, swap, firewall, packages
│   ├── join-server.sh             # Control-plane init and join logic
│   ├── join-worker.sh             # Worker node join logic
│   ├── token.sh                   # Token discovery and join command generator
│   ├── health-check.sh            # Cluster diagnostics (etcd, nodes, pods, CoreDNS)
│   ├── install-cni.sh             # Calico and Cilium CNI installer
│   ├── install-metallb.sh         # MetalLB L2 Bare-Metal Load Balancer installer
│   ├── install-ingress.sh         # Ingress-NGINX and Traefik installer
│   └── setup-lb.sh                # HAProxy API Load Balancer setup
├── manifests/
│   ├── haproxy.cfg.template       # HAProxy configuration template
│   └── metallb-pool.yaml.template # MetalLB IPAddressPool template
└── README.md                      # Complete reference documentation
```

---

## 3. Quickstart Scenarios

### Scenario A: Single-Node All-In-One Lab (or WSL2)

```bash
cd /opt/myproject/k3s
chmod +x k3s.sh scripts/*.sh uninstall.sh

# 1. Initialize Control Plane
sudo ./k3s.sh server-init

# 2. Verify Health
sudo ./k3s.sh health-check

# 3. View Nodes
sudo k3s kubectl get nodes -o wide
```

---

### Scenario B: 3-Control-Plane HA Cluster + 3 Workers

Assuming nodes:
- `CP1`: `10.10.10.10`
- `CP2`: `10.10.10.11`
- `CP3`: `10.10.10.12`
- `W1` : `10.10.10.20`
- `W2` : `10.10.10.21`
- `W3` : `10.10.10.22`
- `LB` : `10.10.10.100` (or use CP1 IP as initial endpoint)

#### Step 1: On CP1 (Initialize Cluster)
```bash
sudo ROLE=server-init NODE_IP=10.10.10.10 ./k3s.sh
```
Retrieve the cluster join token:
```bash
sudo ./k3s.sh token
```

#### Step 2: On CP2 (Join Control Plane)
```bash
sudo ROLE=server-join \
     NODE_IP=10.10.10.11 \
     K3S_URL=https://10.10.10.10:6443 \
     K3S_TOKEN="<TOKEN>" \
     ./k3s.sh
```

#### Step 3: On CP3 (Join Control Plane)
```bash
sudo ROLE=server-join \
     NODE_IP=10.10.10.12 \
     K3S_URL=https://10.10.10.10:6443 \
     K3S_TOKEN="<TOKEN>" \
     ./k3s.sh
```

#### Step 4: Setup API Load Balancer (On LB Node or CP1)
```bash
sudo ./k3s.sh lb 10.10.10.10 10.10.10.11 10.10.10.12
```

#### Step 5: On Worker Nodes (W1, W2, W3)
```bash
sudo ROLE=worker \
     K3S_URL=https://10.10.10.100:6443 \
     K3S_TOKEN="<TOKEN>" \
     ./k3s.sh
```

#### Step 6: Verify Quorum & Nodes from CP1
```bash
sudo ./k3s.sh health-check
```

---

## 4. Advanced Add-Ons

### Calico CNI (for NetworkPolicy practice)
Set in `config/cluster.env`:
```bash
CNI_PLUGIN="calico"
```
Or deploy after initial server install:
```bash
sudo ./k3s.sh cni calico
```

### MetalLB (Bare-metal LoadBalancer IP Provider)
```bash
# Provide IP address pool from your local network
sudo ./k3s.sh metallb 10.10.10.200-10.10.10.220
```

### Ingress-NGINX
```bash
sudo ./k3s.sh ingress nginx
```

---

## 5. CKA Exam Practice Scenarios

### Lab 1: etcd Backup and Restore
1. **Take an instant etcd snapshot**:
   ```bash
   sudo k3s etcd-snapshot save --name cka-backup-01
   sudo k3s etcd-snapshot list
   ```
2. **Simulate failure**: Create a test namespace `kubectl create ns cka-test`, then restore:
   ```bash
   sudo systemctl stop k3s
   sudo k3s server --cluster-reset --cluster-reset-restore-path=/var/lib/rancher/k3s/server/db/snapshots/cka-backup-01
   sudo systemctl start k3s
   ```

### Lab 2: Node Maintenance (Drain & Cordon)
```bash
# Cordon node
kubectl cordon worker1

# Evict pods safely
kubectl drain worker1 --ignore-daemonsets --delete-emptydir-data

# Uncordon after maintenance
kubectl uncordon worker1
```

### Lab 3: Cluster Upgrade Simulation
Edit `config/cluster.env` and set `K3S_VERSION="v1.31.5+k3s1"`, then re-run `./k3s.sh server-init` or `./k3s.sh worker` sequentially across nodes.

---

## 6. Windows & WSL2 Specific Notes

1. Ensure **WSL2 Ubuntu** has systemd enabled in `/etc/wsl.conf`:
   ```ini
   [boot]
   systemd=true
   ```
2. Run `wsl --shutdown` from PowerShell once to apply.
3. Access Kubernetes externally from Windows using `kubectl`:
   Copy `/etc/rancher/k3s/k3s.yaml` to `%USERPROFILE%\.kube\config` and change `127.0.0.1` to `localhost`.

---

## 7. Cluster Teardown / Reset

To completely remove K3s and revert network changes:
```bash
sudo ./k3s.sh uninstall --purge-iptables
```
