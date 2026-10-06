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

> **Note on `NODE_IP`**: `10.10.10.10` in this walkthrough is an illustrative IP for CP1. In single-node labs or local WSL2 environments, omit `NODE_IP` (e.g., `sudo ROLE=server-init ./k3s.sh` or `sudo ./k3s.sh server-init`) to let the script auto-detect your active interface IP, or substitute your machine's real IP. Specifying an IP that is not bound to a local network interface will cause CNI networking to fail.
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

### Cilium CNI (Default eBPF Networking)
Cilium is configured as the default CNI plugin (`CNI_PLUGIN="cilium"` in `config/cluster.env`). When initializing the cluster (`server-init`), Flannel is disabled and Cilium is deployed automatically.

To deploy or reinstall Cilium manually:
```bash
sudo ./k3s.sh cni cilium
```

### Alternative CNIs: Calico or Flannel
To use Calico for NetworkPolicy practice, or the embedded Flannel CNI, set in `config/cluster.env` or pass as a runtime variable:
```bash
# To use Calico:
sudo ROLE=server-init CNI_PLUGIN=calico ./k3s.sh
# or after server install:
sudo ./k3s.sh cni calico

# To use embedded Flannel:
sudo ROLE=server-init CNI_PLUGIN=flannel ./k3s.sh
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


### Lab 4: Troubleshooting a `NotReady` Worker Node (Real Prod Issue)
**Scenario**: A worker node shows as `NotReady` in `kubectl get nodes`. Workloads on it are failing. In production, this can be caused by service crashes, certificate expiration, or misconfigurations.
**Resolution**:
```bash
# 1. Check the node status
kubectl describe node worker1
# Look at conditions like 'Ready', 'MemoryPressure', 'DiskPressure'

# 2. SSH into the failing worker node
ssh worker1

# 3. Check the k3s-agent service logs (since K3s embeds the kubelet in the agent)
sudo journalctl -u k3s-agent -f
# Look for errors like "failed to connect to apiserver" or "invalid token"

# 4. Fix the misconfiguration
# E.g., if the token is wrong in the service file or environment variables
sudo vi /etc/systemd/system/k3s-agent.service.env
# Update K3S_TOKEN to the correct value

# 5. Restart the agent service
sudo systemctl daemon-reload
sudo systemctl restart k3s-agent

# 6. Verify the node returns to 'Ready'
kubectl get nodes
```

### Lab 5: Troubleshooting Network Policies with Cilium
**Scenario**: A frontend pod is timing out when connecting to a backend service in the `prod` namespace due to default-deny NetworkPolicies.
**Resolution**:
```bash
# 1. Test connectivity
kubectl exec -it frontend -n prod -- curl -v http://backend-svc:80
# Result: Connection Timed Out

# 2. Inspect NetworkPolicies in the namespace
kubectl get networkpolicies -n prod
kubectl describe networkpolicy <policy-name> -n prod

# 3. Notice the policy only allows ingress from pods with the label 'tier: frontend'.
# But the frontend pod only has 'tier: web'.

# 4. Update the pod label to match the policy requirement
kubectl label pod frontend -n prod tier=frontend --overwrite

# 5. Verify connectivity is restored
kubectl exec -it frontend -n prod -- curl -v http://backend-svc:80
```

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
