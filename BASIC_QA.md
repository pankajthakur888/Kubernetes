# Certified Kubernetes Administrator (CKA) & Fundamentals: 95 Core Questions & Answers

A comprehensive, production-grade guide containing **95 essential Kubernetes questions and answers**. This guide covers core concepts, architecture, CLI commands, YAML manifests, and troubleshooting aligned with the 14 CKA exam domains and real-world DevOps practices.

---

## Table of Contents
1. [Phase 1: Architecture & Core Components (Q1 - Q8)](#phase-1-architecture--core-components)
2. [Phase 2: Pods, Pod Lifecycle & Multi-Container Pods (Q9 - Q16)](#phase-2-pods-pod-lifecycle--multi-container-pods)
3. [Phase 3: Deployments, ReplicaSets & Rollouts (Q17 - Q24)](#phase-3-deployments-replicasets--rollouts)
4. [Phase 4: Services & Core Networking (Q25 - Q32)](#phase-4-services--core-networking)
5. [Phase 5: Ingress & Network Policies (Q33 - Q38)](#phase-5-ingress--network-policies)
6. [Phase 6: ConfigMaps & Secrets (Q39 - Q45)](#phase-6-configmaps--secrets)
7. [Phase 7: Storage - Volumes, PV, PVC & StorageClasses (Q46 - Q52)](#phase-7-storage---volumes-pv-pvc--storageclasses)
8. [Phase 8: Workloads - DaemonSets, StatefulSets, Jobs & CronJobs (Q53 - Q59)](#phase-8-workloads---daemonsets-statefulsets-jobs--cronjobs)
9. [Phase 9: Scheduling, Taints, Tolerations & Affinity (Q60 - Q66)](#phase-9-scheduling-taints-tolerations--affinity)
10. [Phase 10: Resource Management, Quotas & Autoscaling (Q67 - Q72)](#phase-10-resource-management-quotas--autoscaling)
11. [Phase 11: Health Checks & Container Probes (Q73 - Q77)](#phase-11-health-checks--container-probes)
12. [Phase 12: Security, ServiceAccounts & RBAC (Q78 - Q84)](#phase-12-security-serviceaccounts--rbac)
13. [Phase 13: Cluster Maintenance, Upgrades & Node Drain (Q85 - Q89)](#phase-13-cluster-maintenance-upgrades--node-drain)
14. [Phase 14: Troubleshooting & etcd Backup/Restore (Q90 - Q95)](#phase-14-troubleshooting--etcd-backuprestore)
15. [Architecture Guide: How to Decide Which Workload Controller to Use](#architecture-guide-how-to-decide-which-kubernetes-workload-controller-to-use)

---

## Phase 1: Architecture & Core Components

### Q1: What is Kubernetes, and what core problems does it solve compared to running standalone Docker containers?
**A:** Kubernetes (K8s) is an open-source container orchestration platform that automates the deployment, scaling, networking, and management of containerized applications.
- **Problems solved:**
  - **Self-Healing:** Automatically restarts failed containers, replaces pods, and reschedules them when nodes die.
  - **Service Discovery & Load Balancing:** Assigns stable DNS names and IP addresses, distributing network traffic across healthy pods.
  - **Automated Rollouts & Rollbacks:** Manages zero-downtime updates and reverts changes if failures occur.
  - **Horizontal Auto-Scaling:** Scales applications up or down based on CPU/RAM or custom event metrics.
  - **Storage Orchestration:** Automatically mounts local, cloud, or network storage systems (NFS, AWS EBS, Ceph).

---

### Q2: What are the key components of the Kubernetes Control Plane, and what does each component do?
**A:** The Control Plane makes global decisions about the cluster (scheduling, event response, desired state):
1. **kube-apiserver:** The central REST API gateway. Authenticates, authorizes, validates, and exposes cluster endpoints. All components interact solely through the API server.
2. **etcd:** A distributed, consistent key-value store that holds the complete cluster state, configuration, and secrets.
3. **kube-scheduler:** Watches for newly created Pods with no assigned node and selects the best worker node based on resource availability, taints, affinity, and constraints.
4. **kube-controller-manager:** Runs core controller reconciliation loops (Node Controller, Deployment Controller, ReplicaSet Controller, ServiceAccount Controller).
5. **cloud-controller-manager:** Integrates with underlying cloud provider APIs (load balancers, node routing, persistent volumes).

---

### Q3: What are the worker node components, and what are their responsibilities?
**A:** Worker nodes run application workloads:
1. **kubelet:** The primary node agent. Watches the API server for PodSpecs assigned to its node and ensures the specified containers are running and healthy. Communicates with the container runtime via CRI.
2. **kube-proxy:** A network proxy running on each node that maintains network rules (using iptables or IPVS) to route Service traffic to the correct backend Pods.
3. **Container Runtime (CRI):** The underlying container engine that downloads images and executes containers (e.g., `containerd`, `CRI-O`).

---

### Q4: What is `etcd`, why is it critical, and why must it run as an odd number of replicas (quorum)?
**A:** `etcd` is the single source of truth for the entire cluster. If `etcd` is lost or corrupted, all cluster state and metadata are lost.
- It uses the **Raft consensus algorithm**, which requires a majority **Quorum** to elect a leader and commit writes:
  $$\text{Quorum} = \lfloor N / 2 \rfloor + 1$$
- Running an odd number of nodes ($3, 5, 7$) avoids split-brain scenarios:
  - A 3-node cluster tolerates $1$ failure (Quorum = $2$).
  - A 4-node cluster also tolerates only $1$ failure (Quorum = $3$), adding complexity without increasing fault tolerance.
  - A 5-node cluster tolerates $2$ failures (Quorum = $3$).

---

### Q5: What is the difference between CRI, CNI, and CSI?
**A:** Kubernetes uses standardized plugin interfaces to remain modular:
- **CRI (Container Runtime Interface):** Interface between Kubelet and the container engine (`containerd`, `CRI-O`) to pull images and run container processes.
- **CNI (Container Network Interface):** Interface for configuring network interfaces, IP assignment, and overlay routing across pods (`Cilium`, `Calico`, `Flannel`).
- **CSI (Container Storage Interface):** Interface for attaching, formatting, and mounting external storage volumes into pods (`AWS EBS CSI`, `Ceph CSI`, `Local-Path`).

---

### Q6: How do you check the status and health of the control plane and worker nodes?
**A:**
```bash
# Check node readiness, roles, version, and IPs
kubectl get nodes -o wide

# Check control-plane static pods running in kube-system
kubectl get pods -n kube-system -l tier=control-plane

# View detailed node condition events (DiskPressure, MemoryPressure, PIDPressure)
kubectl describe node <node-name>
```

---

### Q7: What are Static Pods, where are their manifests stored, and who manages them?
**A:** Static Pods are managed **directly by the local Kubelet daemon** on a node without the API server or scheduler being required.
- **Manifest Location:** Typically `/etc/kubernetes/manifests/` (defined by `--pod-manifest-path` in Kubelet configuration).
- **Control Plane Usage:** Kubeadm bootstraps `kube-apiserver`, `kube-controller-manager`, `kube-scheduler`, and `etcd` as Static Pods.
- Kubelet automatically monitors the directory; creating, modifying, or deleting a YAML file immediately creates or restarts the corresponding pod. Kubelet creates a mirror pod in the API server so it is visible via `kubectl get pods`.

---

### Q8: What is the difference between declarative (`kubectl apply`) and imperative (`kubectl create`/`run`) management?
**A:**
- **Imperative Management:** Tells Kubernetes *what action to take* immediately (e.g., `kubectl create deployment web --image=nginx`). Ideal for fast exam tasks, testing, and debugging.
- **Declarative Management:** Tells Kubernetes *what desired state you want* in YAML/JSON files (e.g., `kubectl apply -f app.yaml`). Kubernetes compares the current state, desired state, and last-applied configuration (three-way merge). Ideal for GitOps and production CI/CD.

---

## Phase 2: Pods, Pod Lifecycle & Multi-Container Pods

### Q9: What is a Pod, and why does Kubernetes run Pods instead of individual containers directly?
**A:** A Pod is the smallest deployable computing unit in Kubernetes. It represents a single instance of a running process in the cluster.
- **Why Pods?** Multiple tightly-coupled containers (e.g., an application and a logging sidecar) need to:
  1. Share the exact same network namespace (same IP address, localhost loopback communication).
  2. Share storage volumes mounted across containers.
  3. Share IPC (Inter-Process Communication) and system hostnames.

---

### Q10: How do you create an NGINX pod imperatively and output its YAML definition without creating it (`dry-run`)?
**A:**
```bash
# Generate clean YAML template
kubectl run nginx-pod --image=nginx:alpine --dry-run=client -o yaml > pod.yaml

# Create the pod directly
kubectl run nginx-pod --image=nginx:alpine --port=80
```

---

### Q11: What are the different Pod phases (statuses), and what does each phase mean?
**A:**
1. **Pending:** Pod accepted by the cluster, but one or more containers are not yet created (e.g., downloading image or waiting for a node to be scheduled).
2. **Running:** Pod bound to a node, all containers created, and at least one container is running or starting.
3. **Succeeded:** All containers in the Pod terminated successfully (Exit Code 0) and will not be restarted (common for Jobs).
4. **Failed:** All containers terminated, and at least one container terminated in failure (non-zero exit code).
5. **Unknown:** State could not be obtained, typically due to communication loss between API Server and Kubelet.

---

### Q12: What causes a pod to enter the `CrashLoopBackOff` state, and how do you debug it?
**A:** `CrashLoopBackOff` means a container repeatedly starts, crashes, and Kubelet backs off with an exponential delay before trying to restart it again.
- **Common causes:** Application runtime errors (syntax error, unhandled exception), missing environment variables/secrets, container process exiting immediately (e.g., command finished), failed health probes, or OOMKilled.
- **Debugging steps:**
  ```bash
  # 1. Check exit code and last termination reason
  kubectl describe pod <pod-name>
  
  # 2. View current logs
  kubectl logs <pod-name>
  
  # 3. View previous container crash logs
  kubectl logs <pod-name> --previous
  ```

---

### Q13: What is an Init Container, and how does it differ from a regular app container?
**A:** Init Containers run and must run to completion (Exit Code 0) sequentially **before** any application containers start.
- If an Init Container fails, Kubelet restarts it until it succeeds (unless `restartPolicy: Never`).
- **Use cases:** Waiting for a database service to become available, running database migrations, pre-downloading certificates or configuration files.
```yaml
spec:
  initContainers:
  - name: wait-for-db
    image: busybox:1.28
    command: ['sh', '-c', 'until nc -z db-service 5432; do sleep 2; done;']
  containers:
  - name: app
    image: my-app:v1
```

---

### Q14: What is a Sidecar Container, and how do two containers in the same Pod communicate with each other?
**A:** A Sidecar is a secondary container running alongside the main application container to extend or augment its functionality (e.g., Envoy proxy, Fluentd log shipper).
- **Communication:**
  - **Networking:** Over `localhost:<port>` (both share the same network namespace and IP).
  - **Filesystem:** Through a shared `emptyDir` volume mounted into both containers.

---

### Q15: What is the `restartPolicy` of a Pod, and what are its allowed values?
**A:** The `restartPolicy` defines what Kubelet does when a container exits:
1. **Always (Default):** Restarts container upon any termination. Required for long-running Deployments/DaemonSets.
2. **OnFailure:** Restarts container only if it exits with a non-zero exit code. Used for batch Jobs.
3. **Never:** Never restarts the container regardless of exit status.

---

### Q16: How do you view logs of a specific container in a multi-container Pod, and how do you execute commands inside it?
**A:**
```bash
# View logs of container 'logger'
kubectl logs <pod-name> -c logger -f

# Execute bash interactive shell in container 'app'
kubectl exec -it <pod-name> -c app -- /bin/sh

# Check previous instance logs of container 'app'
kubectl logs <pod-name> -c app --previous
```

---

## Phase 3: Deployments, ReplicaSets & Rollouts

### Q17: What is the relationship between a Deployment, a ReplicaSet, and a Pod?
**A:**
- **Deployment:** The top-level declarative controller. Manages declarative updates, rollout history, revision pausing, and rollbacks.
- **ReplicaSet:** Managed directly by the Deployment. Ensures that a specified number of identical Pod replicas are running at any given time based on label selectors.
- **Pod:** The actual running workload instances created and destroyed by the ReplicaSet.
$$\text{Deployment} \longrightarrow \text{ReplicaSet} \longrightarrow \text{Pods}$$

---

### Q18: How do you create a Deployment named `web` with 3 replicas of `nginx:1.24` and scale it to 5 replicas?
**A:**
```bash
# Create deployment
kubectl create deployment web --image=nginx:1.24 --replicas=3

# Scale deployment imperatively
kubectl scale deployment web --replicas=5
```

---

### Q19: What deployment update strategies does Kubernetes support (RollingUpdate vs Recreate)?
**A:**
1. **RollingUpdate (Default):** Gradually replaces old pods with new pods with zero downtime. Ensures a minimum number of pods remain available throughout the rollout.
2. **Recreate:** Kills all existing pods simultaneously before spinning up any new pods. Causes downtime, but necessary when two versions cannot run concurrently (e.g., shared non-backward-compatible database migrations).

---

### Q20: What are `maxSurge` and `maxUnavailable` in a RollingUpdate deployment strategy?
**A:**
- **`maxSurge`:** The maximum number of Pods that can be scheduled *above* the desired replica count during an update (e.g., `25%` or `1`).
- **`maxUnavailable`:** The maximum number of Pods that can be unavailable *below* the desired replica count during the update (e.g., `25%` or `0`).
```yaml
spec:
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0  # Guarantees 100% capacity maintained during updates
```

---

### Q21: How do you update a Deployment image to `nginx:1.25` and view its rollout status in real-time?
**A:**
```bash
# Set new image
kubectl set image deployment/web nginx=nginx:1.25 --record

# Monitor rollout status
kubectl rollout status deployment/web
```

---

### Q22: How do you view the rollout history of a Deployment and roll it back to the previous revision?
**A:**
```bash
# View revision history
kubectl rollout history deployment/web

# Inspect a specific revision
kubectl rollout history deployment/web --revision=2

# Roll back to the immediately previous revision
kubectl rollout undo deployment/web

# Roll back to a specific revision
kubectl rollout undo deployment/web --to-revision=1
```

---

### Q23: How do you pause and resume a Deployment rollout?
**A:**
```bash
# Pause rollout (useful for making multiple changes before triggering pods recreation)
kubectl rollout pause deployment/web

# Resume rollout
kubectl rollout resume deployment/web
```

---

### Q24: How do you restart all pods in a Deployment without changing its pod specification?
**A:**
```bash
# Performs a zero-downtime rolling restart
kubectl rollout restart deployment/web
```
*(Under the hood, this sets an annotation `kubectl.kubernetes.io/restartedAt` with current timestamp in the Pod template, triggering a RollingUpdate).*

---

## Phase 4: Services & Core Networking

### Q25: Why do we need a Kubernetes Service when Pods already have IP addresses?
**A:** Pods are ephemeral; they are created and destroyed dynamically during scaling, crashes, and node updates. Each time a pod is recreated, it receives a brand-new IP address.
A **Service** provides an immutable, long-lived IP address (`ClusterIP`) and DNS name that load-balances traffic across an ever-changing set of healthy backend Pods.

---

### Q26: What are the four Service types in Kubernetes, and when would you use each?
**A:**
1. **ClusterIP (Default):** Exposes the Service on an internal cluster-only IP. Reachable only inside the cluster.
2. **NodePort:** Exposes the Service on a static high-range port (`30000-32767`) on every cluster node's IP. External clients can reach `<NodeIP>:<NodePort>`.
3. **LoadBalancer:** Provisions an external Cloud Load Balancer (AWS NLB, GCP LB) that routes directly to NodePort/ClusterIP.
4. **ExternalName:** Maps the Service to an external DNS CNAME record (e.g., `my-db.external.com`) without proxying traffic.

---

### Q27: What is a `ClusterIP` Service, and how does service discovery work inside the cluster (CoreDNS)?
**A:** CoreDNS monitors Services and creates DNS A/AAAA records.
- Standard DNS format:
  $$\text{<service-name>.<namespace>.svc.cluster.local}$$
- If Pod and Service are in the same namespace, querying `curl http://backend-svc:8080` resolves directly via CoreDNS.

---

### Q28: What is a `NodePort` Service, what is the default port range, and how does external traffic reach it?
**A:** Exposes the application on a dedicated port between **`30000` and `32767`** on every worker and control-plane node.
- Incoming traffic hitting `http://<Any-Node-IP>:<NodePort>` is intercepted by `kube-proxy`, which DNATs the request and forwards it to one of the backend Pods.

---

### Q29: What is a `LoadBalancer` Service, and how does it differ on cloud providers vs bare-metal?
**A:**
- **On Cloud (AWS/GCP/Azure):** The cloud controller manager detects the Service and calls the cloud provider's API to provision a managed cloud load balancer (e.g., AWS NLB), assigning a public external IP/FQDN.
- **On Bare-Metal / On-Premise:** By default, the Service stays in `<Pending>` External IP forever unless an on-premise load balancer controller like **MetalLB** is installed to advertise VIPs via ARP/BGP.

---

### Q30: What are Kubernetes Endpoints and EndpointSlices, and what happens if a Service selector doesn't match any pods?
**A:**
- **Endpoints / EndpointSlices:** Track the real, active IP addresses and ports of the pods that match the Service's `selector`.
- If the selector does not match any pods (e.g., typo in label `app: web` vs `app: weba`), the Endpoints object is empty. The Service IP exists, but any requests to it result in **`Connection refused`** or timeout.
```bash
kubectl get endpoints <service-name>
kubectl get endpointslices
```

---

### Q31: What is the difference between `port`, `targetPort`, and `nodePort` in a Service definition?
**A:**
- **`port`:** The port exposed **internally on the Service's ClusterIP** (what other pods send traffic to).
- **`targetPort`:** The port **the container inside the Pod is listening on** (where traffic is forwarded).
- **`nodePort`:** The port opened **on all cluster nodes** for external traffic (`30000-32767`).
```yaml
spec:
  ports:
  - port: 80         # Service ClusterIP port
    targetPort: 8080 # Pod container port
    nodePort: 31000  # Physical host port
```

---

### Q32: How do you expose a Deployment named `backend` on port 8080 targeting container port 80 using `kubectl expose`?
**A:**
```bash
kubectl expose deployment backend --name=backend-svc --port=8080 --target-port=80 --type=ClusterIP
```

---

## Phase 5: Ingress & Network Policies

### Q33: What is an Ingress resource, and how does it differ from a NodePort or LoadBalancer Service?
**A:** An Ingress manages external HTTP and HTTPS routing into the cluster at **Layer 7 (Application Layer)**:
- Provides host-based routing (e.g., `api.example.com` vs `web.example.com`) and path-based routing (e.g., `/orders` vs `/catalog`).
- Provides centralized TLS/SSL termination.
- Saves cloud costs: you only pay for **one** Cloud Load Balancer, routing traffic to dozens of internal ClusterIP Services.

---

### Q34: What is an Ingress Controller, and why won't creating an Ingress resource do anything without one?
**A:** An Ingress resource is just a declarative configuration specification stored in etcd.
An **Ingress Controller** (e.g., Ingress-NGINX, Traefik, HAProxy, Envoy) is the actual reverse-proxy daemon watching the API Server for Ingress resources and reconfiguring its routing tables to route traffic to the backend pods. Without an active Ingress Controller, Ingress resources have no effect.

---

### Q35: How do you create an Ingress rule that routes host `api.example.com` to service `api-svc:80`?
**A:**
```bash
kubectl create ingress api-ingress \
  --rule="api.example.com/*=api-svc:80"
```
Or via YAML:
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: api-ingress
spec:
  rules:
  - host: api.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: api-svc
            port:
              number: 80
```

---

### Q36: What is a NetworkPolicy, and are pod communications allowed or blocked by default in Kubernetes?
**A:** By default, Kubernetes operates on a flat, non-isolated network: **all pods can communicate with all other pods across all namespaces without restriction**.
A **NetworkPolicy** acts as an internal firewall at Layer 3/4. Once a NetworkPolicy selects a pod, that pod enters an **isolated mode**, blocking all traffic that is not explicitly allowed.
*(Note: Requires a CNI that enforces policies, such as Calico or Cilium; standard Flannel ignores NetworkPolicies).*

---

### Q37: How do you create a default deny-all ingress NetworkPolicy for a namespace?
**A:**
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all-ingress
  namespace: prod
spec:
  podSelector: {} # Selects all pods in the namespace
  policyTypes:
  - Ingress       # Ingress rules empty -> blocks all incoming traffic
```

---

### Q38: How do you create a NetworkPolicy that only allows ingress traffic to pods with label `app: db` from pods with label `app: api` on port 5432?
**A:**
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-api-to-db
spec:
  podSelector:
    matchLabels:
      app: db
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: api
    ports:
    - protocol: TCP
      port: 5432
```

---

## Phase 6: ConfigMaps & Secrets

### Q39: What is a ConfigMap, and what are the different ways to create one?
**A:** A ConfigMap stores non-confidential configuration data as key-value pairs.
- **Ways to create:**
  ```bash
  # 1. From literal values
  kubectl create configmap app-cfg --from-literal=ENV=production --from-literal=LOG_LEVEL=info
  
  # 2. From a file
  kubectl create configmap app-cfg --from-file=config.properties
  
  # 3. From an env file
  kubectl create configmap app-cfg --from-env-file=.env
  ```

---

### Q40: How do you inject a ConfigMap into a Pod as environment variables?
**A:**
```yaml
spec:
  containers:
  - name: app
    image: my-app
    env:
      - name: ENVIRONMENT
        valueFrom:
          configMapKeyRef:
            name: app-cfg
            key: ENV
    # Or import ALL keys as env vars at once:
    envFrom:
      - configMapRef:
          name: app-cfg
```

---

### Q41: How do you mount a ConfigMap as individual files inside a container volume?
**A:**
```yaml
spec:
  containers:
  - name: web
    image: nginx
    volumeMounts:
    - name: config-volume
      mountPath: /etc/nginx/conf.d
  volumes:
  - name: config-volume
    configMap:
      name: nginx-config
```

---

### Q42: What is a Kubernetes Secret, how is it encoded by default, and how does it differ from a ConfigMap?
**A:** Secrets store sensitive information (passwords, tokens, SSH keys, certificates).
- **Difference:** Secrets are stored as **Base64 encoded strings** in YAML, whereas ConfigMaps store plaintext.
- **Important:** Base64 is **encoding**, not encryption. Anyone with access to the Secret can decode it with `echo "<base64>" | base64 -d`.

---

### Q43: What are the standard types of Secrets in Kubernetes?
**A:**
1. **`Opaque` (Default):** Arbitrary user-defined key-value sensitive data.
2. **`kubernetes.io/tls`:** Stores TLS certificate and private key (`tls.crt`, `tls.key`).
3. **`kubernetes.io/dockerconfigjson`:** Stores Docker registry credentials to authenticate image pulls (`imagePullSecrets`).
4. **`kubernetes.io/service-account-token`:** Legacy ServiceAccount authorization token.

---

### Q44: How do you create a TLS Secret containing `tls.crt` and `tls.key`?
**A:**
```bash
kubectl create secret tls app-tls-secret \
  --cert=path/to/tls.crt \
  --key=path/to/tls.key
```

---

### Q45: Are Kubernetes Secrets encrypted at rest by default, and how do you secure them in production?
**A:** **No.** By default, etcd stores Secrets as unencrypted plaintext.
- **Production hardening:**
  1. Enable **Encryption at Rest** in `kube-apiserver` using an `EncryptionConfiguration` file with KMS (AWS KMS, HashiCorp Vault).
  2. Implement strict **RBAC** limiting `get`/`list` Secret verbs.
  3. Use external secret operators like **External Secrets Operator (ESO)** or HashiCorp Vault Agent.

---

## Phase 7: Storage - Volumes, PV, PVC & StorageClasses

### Q46: What is an `emptyDir` volume, and when should you use it?
**A:** An `emptyDir` volume is created when a Pod is assigned to a node and exists as long as that Pod is running on that node.
- Starts out empty; all containers in the Pod can read and write the same files.
- **Data Lifecycle:** Data is permanently deleted when the Pod is deleted or evicted. Survives container crashes.
- **Use cases:** Scratch space, caching, temporary file transformations, sharing data between an app container and a sidecar.

---

### Q47: What is a `hostPath` volume, and why is it dangerous in multi-node production clusters?
**A:** A `hostPath` mounts a file or directory from the host node's filesystem directly into the Pod.
- **Why dangerous:** If the pod is rescheduled to a different node, the new node will not have the previous node's files. It also creates a security risk by granting containers access to root host filesystems (`/var/run/docker.sock`, `/etc`).

---

### Q48: What is the difference between a PersistentVolume (PV) and a PersistentVolumeClaim (PVC)?
**A:**
- **PersistentVolume (PV):** A cluster-wide storage resource provisioned by an administrator or dynamically by a StorageClass. Has an independent lifecycle decoupled from any Pod.
- **PersistentVolumeClaim (PVC):** A request for storage by a developer/user (specifying capacity and access modes). Kubernetes matches and binds the PVC to a suitable PV.
$$\text{Pod} \longrightarrow \text{PVC} \longrightarrow \text{PV} \longrightarrow \text{Underlying Storage (NFS, EBS)}$$

---

### Q49: What are the three standard PersistentVolume access modes (`ReadWriteOnce`, `ReadOnlyMany`, `ReadWriteMany`)?
**A:**
1. **ReadWriteOnce (RWO):** Volume can be mounted as read-write by a **single node** (common for block storage like AWS EBS).
2. **ReadOnlyMany (ROX):** Volume can be mounted as read-only by **many nodes** concurrently.
3. **ReadWriteMany (RWX):** Volume can be mounted as read-write by **many nodes** simultaneously (requires network filesystems like NFS, CephFS, AWS EFS).
4. *(New in v1.22+)* **ReadWriteOncePod (RWOP):** Can be mounted by a **single pod**.

---

### Q50: What are PersistentVolume reclaim policies (`Retain`, `Delete`, `Recycle`)?
**A:** Defines what happens to the PV when its bound PVC is deleted:
1. **Retain (Default):** The PV remains intact. Data is preserved. The volume enters `Released` state and cannot be bound by another claim until manually scrubbed.
2. **Delete:** The underlying storage asset (e.g., AWS EBS volume) is automatically deleted from cloud infrastructure immediately.
3. **Recycle (Deprecated):** Performs basic scrub (`rm -rf /volume/*`) to allow re-binding.

---

### Q51: What is a StorageClass, and how does dynamic volume provisioning work?
**A:** A `StorageClass` describes the parameters and provisioner (CSI driver) used for storage.
- **Dynamic Provisioning:** Instead of an admin manually creating PVs ahead of time, when a user creates a PVC requesting a StorageClass, the StorageClass provisioner automatically calls the storage backend (e.g., cloud API), creates the disk, and provisions a PV on-the-fly.

---

### Q52: Why is a PVC stuck in `Pending` state, and how do you troubleshoot it?
**A:**
- **Reasons:**
  1. No existing PV matches the requested capacity, accessMode, or storageClassName.
  2. The requested `StorageClass` does not exist or its CSI provisioner is crashing.
  3. The StorageClass uses `volumeBindingMode: WaitForFirstConsumer` (normal behavior: waits until a pod using the PVC is scheduled to a node before creating the volume).
- **Troubleshoot:** `kubectl describe pvc <pvc-name>` (check Events section).

---

## Phase 8: Workloads - DaemonSets, StatefulSets, Jobs & CronJobs

### Q53: What is a DaemonSet, and what are common real-world use cases?
**A:** A DaemonSet ensures that all (or some matching) Nodes run exactly **one copy of a Pod**. As nodes are added to the cluster, pods are automatically added to them.
- **Use cases:**
  - Cluster storage daemons (`ceph`, `glusterd`).
  - Log collection agents on every node (`fluentd`, `promtail`).
  - Node monitoring metrics exporters (`node-exporter`).
  - Network CNI daemons (`cilium`, `calico-node`, `kube-proxy`).

---

### Q54: What is a StatefulSet, and what makes it different from a standard Deployment?
**A:** A StatefulSet manages stateful applications requiring persistent identity:
1. **Stable, Unique Network Identifiers:** Pods get sticky, deterministic names (`db-0`, `db-1`, `db-2`) instead of random hashes.
2. **Ordered Deployment & Scaling:** Pods are started sequentially (`db-0` must become Ready before `db-1` starts) and terminated in reverse order.
3. **Stable Persistent Storage:** Uses `volumeClaimTemplates` to guarantee that if `db-0` crashes and reschedules, it automatically reattaches to its exact same dedicated PVC (`data-db-0`).

---

### Q55: What is a Headless Service, and why is it required by StatefulSets?
**A:** A Service with `clusterIP: None`.
- Instead of returning a single load-balanced virtual ClusterIP, CoreDNS returns direct DNS A records for each healthy Pod IP.
- Allows stateful replicas (e.g., database leader/follower) to discover and communicate with each other directly by pod name:
  $$\text{<pod-name>.<headless-svc>.<namespace>.svc.cluster.local}$$

---

### Q56: What is a Kubernetes Job, and what are `completions`, `parallelism`, and `backoffLimit`?
**A:** A Job creates one or more Pods and ensures that a specified number of them successfully terminate (Exit Code 0).
- **`completions`:** Total number of successful pod completions required to finish the Job.
- **`parallelism`:** Maximum number of pods that can run simultaneously.
- **`backoffLimit`:** Number of retries before marking the Job as failed (default is 6).

---

### Q57: What is a CronJob, and how does its schedule syntax work?
**A:** Runs Jobs on a time-based schedule using standard Unix cron format:
```text
# ┌───────────── minute (0 - 59)
# │ ┌───────────── hour (0 - 23)
# │ │ ┌───────────── day of the month (1 - 31)
# │ │ │ ┌───────────── month (1 - 12)
# │ │ │ │ ┌───────────── day of the week (0 - 6) (Sunday to Saturday)
# │ │ │ │ │
# * * * * *
```
Example: `0 2 * * *` (Runs every day at 02:00 AM).

---

### Q58: What is `concurrencyPolicy` in a CronJob (`Allow`, `Forbid`, `Replace`)?
**A:** Specifies how to treat concurrent executions of a Job:
1. **Allow (Default):** Allows concurrently running jobs.
2. **Forbid:** If the previous job has not finished, the new scheduled run is skipped.
3. **Replace:** If the previous job is still running, it is terminated and replaced by the new job.

---

### Q59: How do you manually trigger an immediate one-off Job run from an existing CronJob?
**A:**
```bash
kubectl create job --from=cronjob/nightly-backup manual-backup-01
```

---

## Phase 9: Scheduling, Taints, Tolerations & Affinity

### Q60: How does the Kubernetes Scheduler (`kube-scheduler`) select a node for a pod (Filtering vs Scoring)?
**A:** Two-step algorithm:
1. **Filtering (Predicates):** Filters out nodes that cannot satisfy the pod's requirements (e.g., insufficient CPU/RAM, matching taints without tolerations, port conflicts).
2. **Scoring (Priorities):** Ranks the remaining surviving nodes based on scoring plugins (e.g., image locality, least requested resources) and assigns the pod to the node with the highest score.

---

### Q61: How do you assign a Pod to a specific node using `nodeSelector` vs `nodeName`?
**A:**
- **`nodeName`:** Hardcodes the pod to a specific node by name, **bypassing the scheduler completely**.
- **`nodeSelector`:** The simplest scheduling constraint; matches key-value labels on nodes:
  ```yaml
  nodeSelector:
    disktype: ssd
  ```

---

### Q62: What are Taints and Tolerations, and what are the three taint effects (`NoSchedule`, `PreferNoSchedule`, `NoExecute`)?
**A:**
- **Taint (Node property):** Repels pods that do not have a matching toleration.
- **Toleration (Pod property):** Allows (but does not require) the pod to be scheduled on a node with a matching taint.
- **Taint Effects:**
  1. **`NoSchedule`:** New pods without matching tolerations will not be scheduled on the node. Existing pods remain unaffected.
  2. **`PreferNoSchedule`:** Soft constraint; scheduler tries to avoid the node, but will place the pod there if no other nodes are available.
  3. **`NoExecute`:** Evicts existing pods immediately if they do not tolerate the taint, and prevents new pods from scheduling.

---

### Q63: How do you apply and remove a taint on a node using `kubectl taint`?
**A:**
```bash
# Apply taint
kubectl taint nodes worker1 dedicated=gpu:NoSchedule

# Remove taint (append a hyphen '-' at the end)
kubectl taint nodes worker1 dedicated=gpu:NoSchedule-
```

---

### Q64: What is Node Affinity, and what is the difference between `requiredDuringSchedulingIgnoredDuringExecution` and `preferredDuringSchedulingIgnoredDuringExecution`?
**A:** Node Affinity attracts pods to nodes based on node labels using rich operators (`In`, `NotIn`, `Exists`, `Gt`):
- **`requiredDuringSchedulingIgnoredDuringExecution` (Hard rule):** Pod **cannot** be scheduled unless the rule is satisfied.
- **`preferredDuringSchedulingIgnoredDuringExecution` (Soft rule):** Scheduler attempts to enforce the rule, but will schedule the pod elsewhere if no matching node exists.
- *`IgnoredDuringExecution`* means if node labels change later while the pod is running, the pod will not be evicted.

---

### Q65: What is Pod Anti-Affinity, and how do you ensure two replicas of the same app never run on the same physical host?
**A:** Prevents pods from scheduling on nodes that already run pods matching specific labels:
```yaml
affinity:
  podAntiAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
    - labelSelector:
        matchExpressions:
        - key: app
          operator: In
          values:
          - web
      topologyKey: "kubernetes.io/hostname"
```

---

### Q66: How do you manually schedule a pod if no scheduler is running in the cluster?
**A:** Define the `nodeName` field directly in the Pod specification:
```yaml
spec:
  nodeName: worker1  # Directly binds the pod to worker1, bypassing the scheduler
  containers:
  - name: nginx
    image: nginx
```

---

## Phase 10: Resource Management, Quotas & Autoscaling

### Q67: What is the difference between resource `requests` and resource `limits` for CPU and Memory?
**A:**
- **`requests`:** The minimum guaranteed amount of CPU/Memory allocated for the container. The **scheduler uses requests** to find a node with enough allocatable capacity.
- **`limits`:** The hard maximum ceiling the container is allowed to consume on the node. Enforced by Linux cgroups.

---

### Q68: What happens if a container exceeds its CPU limit vs its Memory limit (`OOMKilled`)?
**A:**
- **Exceeding CPU limit:** CPU is compressible. The container is **throttled** (slowed down by CFS bandwidth control), but the process is **not killed**.
- **Exceeding Memory limit:** Memory is non-compressible. The Linux kernel OOM Killer immediately terminates the container process with **`OOMKilled` (Exit Code 137)**.

---

### Q69: What are the three Kubernetes Quality of Service (QoS) classes (`Guaranteed`, `Burstable`, `BestEffort`)?
**A:** Assigned automatically by Kubernetes to determine eviction priority when a node runs out of memory:
1. **Guaranteed (Safest):** Every container in the pod has CPU and Memory requests equal to limits. Last to be evicted.
2. **Burstable:** Requests and limits are specified, but not equal (or requests < limits). Evicted when no BestEffort pods remain.
3. **BestEffort (First to be killed):** No requests and no limits specified. First to be terminated during node memory pressure.

---

### Q70: What is a ResourceQuota, and what happens when a namespace exceeds its quota?
**A:** A `ResourceQuota` sets hard aggregate resource limits on a namespace (total CPU, total RAM, total number of Pods/Services).
- Once a quota is reached, any request to create or scale up new pods in that namespace is **rejected with an API error** (`exceeded quota`).

---

### Q71: What is a LimitRange, and how does it set default requests/limits for pods that don't specify them?
**A:** A `LimitRange` enforces min/max constraints per individual container or pod within a namespace.
- If a pod manifest omits `resources.requests` or `resources.limits`, the LimitRange automatically injects configured default values during admission control.

---

### Q72: What is the Horizontal Pod Autoscaler (HPA), and how do you configure it to autoscale a deployment between 2 and 10 pods at 80% CPU?
**A:** The HPA automatically increases or decreases the number of pod replicas based on observed CPU utilization or custom metrics.
```bash
kubectl autoscale deployment web --min=2 --max=10 --cpu-percent=80
```
*(Requires the `metrics-server` pod to be running in the cluster).*

---

## Phase 11: Health Checks & Container Probes

### Q73: What is a `livenessProbe`, and what action does Kubernetes take when it fails?
**A:** Determines if the container is still alive and running properly (e.g., detects deadlocks).
- **Failure Action:** Kubelet terminates the container process and **restarts it** according to its `restartPolicy`.

---

### Q74: What is a `readinessProbe`, and what action does Kubernetes take when it fails?
**A:** Determines if the container is ready to accept incoming network traffic.
- **Failure Action:** Kubelet **removes the Pod's IP address from the Endpoints** of all matching Services. The container is **not restarted**, but no traffic will be routed to it until the probe passes again.

---

### Q75: What is a `startupProbe`, and why is it essential for legacy applications with slow boot times?
**A:** Disables liveness and readiness probes until the container has finished its initial startup.
- **Problem solved:** If a legacy application takes 2 minutes to initialize, a standard livenessProbe might kill and restart the container before it ever gets a chance to boot. The startupProbe protects it during this window.

---

### Q76: What probe mechanisms does Kubernetes support (`httpGet`, `tcpSocket`, `exec`, `grpc`)?
**A:**
1. **`httpGet`:** Sends an HTTP GET request; status codes $200 \le \text{code} < 400$ indicate success.
2. **`tcpSocket`:** Attempts to open a TCP socket on the specified port. Success if connection established.
3. **`exec`:** Executes a command inside the container; exit code `0` indicates success.
4. **`grpc`:** Sends a gRPC health check request.

---

### Q77: What do `initialDelaySeconds`, `periodSeconds`, `timeoutSeconds`, and `failureThreshold` control in a probe?
**A:**
- **`initialDelaySeconds`:** Seconds to wait after container starts before performing the first probe.
- **`periodSeconds`:** How often (in seconds) to perform the probe check (default 10s).
- **`timeoutSeconds`:** Seconds after which the probe times out (default 1s).
- **`failureThreshold`:** Number of consecutive failures before taking action (restarting or removing from service).

---

## Phase 12: Security, ServiceAccounts & RBAC

### Q78: What is a ServiceAccount, and how does it differ from a human user account?
**A:**
- **User Account:** Represents a human operator (admin, developer) authenticated via external mechanisms (certificates, OIDC, LDAP). Not stored in the Kubernetes API.
- **ServiceAccount:** An identity created in the Kubernetes API for processes/pods running inside the cluster to authenticate with the API server.

---

### Q79: What is Role-Based Access Control (RBAC), and what is the difference between a `Role` and a `ClusterRole`?
**A:** RBAC regulates access to resources based on roles assigned to users or service accounts:
- **`Role`:** Namespaced. Grants permissions (verbs: `get`, `list`, `watch`, `create`) on resources **only within a specific namespace**.
- **`ClusterRole`:** Cluster-wide. Grants permissions across **all namespaces**, or on non-namespaced resources (like Nodes, PersistentVolumes, `/healthz`).

---

### Q80: What is the difference between a `RoleBinding` and a `ClusterRoleBinding`?
**A:**
- **`RoleBinding`:** Binds a Role (or ClusterRole) to a user/ServiceAccount **within a specific namespace**.
- **`ClusterRoleBinding`:** Binds a ClusterRole to a user/ServiceAccount **across the entire cluster**.

---

### Q81: How do you verify if a ServiceAccount or user has permission to perform an action using `kubectl auth can-i`?
**A:**
```bash
# Check your own permission
kubectl auth can-i create deployments

# Check if ServiceAccount 'app-sa' in namespace 'prod' can delete pods
kubectl auth can-i delete pods -n prod --as=system:serviceaccount:prod:app-sa
```

---

### Q82: What is a `securityContext` at the Pod level vs the Container level?
**A:** Defines privilege and access control settings:
- **Pod-level:** Applies to all containers in the Pod (e.g., `fsGroup`, `runAsUser`).
- **Container-level:** Applies to an individual container and can override pod-level settings (e.g., `privileged`, `capabilities`, `readOnlyRootFilesystem`).

---

### Q83: How do you configure a pod to run as non-root user ID 1000 with a read-only root filesystem?
**A:**
```yaml
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
  containers:
  - name: secure-app
    image: my-app
    securityContext:
      readOnlyRootFilesystem: true
      allowPrivilegeEscalation: false
```

---

### Q84: What are Linux capabilities, and how do you drop all capabilities except `NET_BIND_SERVICE`?
**A:** Linux divides root privileges into distinct units (capabilities).
```yaml
securityContext:
  capabilities:
    drop:
    - ALL
    add:
    - NET_BIND_SERVICE  # Allows binding to ports below 1024 without running as full root
```

---

## Phase 13: Cluster Maintenance, Upgrades & Node Drain

### Q85: What is the difference between `kubectl cordon`, `kubectl drain`, and `kubectl uncordon`?
**A:**
- **`cordon`:** Marks node as `SchedulingDisabled`. Prevents new pods from scheduling, but existing pods continue running.
- **`drain`:** Safely evicts all running pods from the node (triggering their rescheduling elsewhere) and cordons it for maintenance.
- **`uncordon`:** Marks the node as schedulable again.

---

### Q86: What flags are required when draining a node that runs DaemonSets or pods with `emptyDir` storage?
**A:**
```bash
kubectl drain <node-name> \
  --ignore-daemonsets \
  --delete-emptydir-data \
  --force
```

---

### Q87: What is a PodDisruptionBudget (PDB), and how does it protect application availability during maintenance?
**A:** A PDB limits the number of pods of a replicated application that can be down simultaneously from voluntary disruptions (e.g., node draining, cluster autoscaling):
```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: web-pdb
spec:
  minAvailable: 2  # Or maxUnavailable: 1
  selector:
    matchLabels:
      app: web
```

---

### Q88: What is the proper sequence to upgrade a Kubernetes cluster using `kubeadm`?
**A:**
1. Upgrade Control Plane:
   - Upgrade `kubeadm` package.
   - Run `kubeadm upgrade plan`, then `kubeadm upgrade apply v1.x.y`.
   - Upgrade `kubelet` and `kubectl` packages.
   - Restart kubelet (`systemctl daemon-reload && systemctl restart kubelet`).
2. Upgrade Worker Nodes sequentially:
   - Drain node (`kubectl drain <node> --ignore-daemonsets`).
   - Upgrade `kubeadm` on the worker.
   - Run `sudo kubeadm upgrade node`.
   - Upgrade `kubelet` and `kubectl`.
   - Restart kubelet.
   - Uncordon node (`kubectl uncordon <node>`).

---

### Q89: How do you upgrade the control plane node vs worker nodes safely?
**A:** Never upgrade worker nodes before the control plane.
Kubernetes version skew policy mandates that Kubelet versions can be at most 2 minor versions older than kube-apiserver, but **never newer** than kube-apiserver. Always upgrade control plane first, then workers one at a time.

---

## Phase 14: Troubleshooting & etcd Backup/Restore

### Q90: What is your step-by-step methodology when a Pod is stuck in `Pending` state?
**A:**
1. `kubectl describe pod <pod-name>`: Check the **Events** section at the bottom.
2. Check for:
   - **Insufficient CPU/Memory:** Nodes cannot satisfy `resources.requests`.
   - **Taints & Tolerations:** Pod lacks toleration for tainted nodes.
   - **NodeSelector / Affinity mismatch:** No nodes match the label query.
   - **Unbound PVC:** Volume requested is not bound.
   - **No Nodes available:** All nodes are NotReady or Cordoned.

---

### Q91: What is your step-by-step methodology when a Pod is stuck in `ImagePullBackOff` or `ErrImagePull`?
**A:**
1. Check image name and tag typos: `kubectl get pod <pod-name> -o yaml | grep image:`.
2. Verify registry authentication: Ensure `imagePullSecrets` is configured if pulling from a private registry.
3. Test container image pull on the node: SSH into worker node and run `crictl pull <image>`.
4. Check node network / DNS resolution to external registry.

---

### Q92: What is your step-by-step methodology when a Node status changes to `NotReady`?
**A:**
1. Check conditions and events: `kubectl describe node <node-name>`.
2. SSH to node and check Kubelet service:
   `systemctl status kubelet` and `journalctl -u kubelet -n 100 -f`.
3. Check container runtime:
   `systemctl status containerd` and `crictl ps`.
4. Check disk and inodes: `df -h` and `df -i` (Kubelet evicts and marks NotReady if disk is 100% full).
5. Check memory pressure: `free -m`.

---

### Q93: How do you troubleshoot a Service where clients cannot connect to the backend pods?
**A:**
1. Check if Endpoints exist: `kubectl get endpoints <service-name>`.
2. If Endpoints empty: verify that the Service `spec.selector` matches the Pod `metadata.labels` exactly.
3. Check Pod health: Ensure pods are `Running` and readiness probes are passing.
4. Check targetPort: Ensure Service `targetPort` matches the actual port the container application is listening on.
5. Check NetworkPolicies: Verify no policy is blocking traffic on the target port.
6. Test DNS inside cluster: `kubectl run test --rm -it --image=busybox:1.28 -- nslookup <service-name>`.

---

### Q94: How do you take a full snapshot backup of an `etcd` database cluster using `etcdctl`?
**A:**
```bash
ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  snapshot save /var/lib/etcd-backup.db

# Verify snapshot integrity
ETCDCTL_API=3 etcdctl --write-out=table snapshot status /var/lib/etcd-backup.db
```

---

### Q95: How do you restore an `etcd` snapshot, update static pod manifests, and verify cluster restoration?
**A:**
```bash
# 1. Restore snapshot to a new data directory
ETCDCTL_API=3 etcdctl \
  --data-dir=/var/lib/etcd-restored \
  snapshot restore /var/lib/etcd-backup.db

# 2. Update the static pod manifest for etcd
# Edit /etc/kubernetes/manifests/etcd.yaml:
# Change the hostPath volume mount from /var/lib/etcd to /var/lib/etcd-restored

# 3. Kubelet automatically detects manifest change and restarts etcd container:
watch crictl ps

# 4. Verify cluster health:
kubectl get nodes
kubectl get pods -A
```

---

## Architecture Guide: How to Decide Which Kubernetes Workload Controller to Use

Choosing the correct Kubernetes workload controller is one of the most critical architectural decisions in system design. Selecting the wrong controller leads to **data corruption**, **service downtime**, **resource starvation**, or **deployment loops**.

---

### 1. The Workload Decision Tree

Follow this step-by-step decision flowchart when designing any new application on Kubernetes:

```text
                                  What type of workload are you running?
                                                     │
                     ┌───────────────────────────────┴───────────────────────────────┐
                     ▼                                                               ▼
        [ Continuous / Long-Running ]                                   [ Finite / Run-to-Completion ]
                     │                                                               │
     Does it need to run on EVERY node?                              Is it scheduled by time or by events?
          ┌──────────┴──────────┐                                         ┌──────────┴──────────┐
          ▼                     ▼                                         ▼                     ▼
        (Yes)                  (No)                                   [ Time-Based ]       [ Event / Batch ]
          │                     │                                     (e.g., Cron)      (e.g., DB Migration)
          ▼                     ▼                                         │                     │
      DaemonSet       Does it require state,                              ▼                     ▼
      (Monitoring,   sticky identity, or unique                         CronJob                Job
       Loggers, CNI) persistent storage per pod?                                            (or KEDA
                                ┌───────┴───────┐                                           ScaledJob)
                                ▼               ▼
                              (Yes)            (No)
                                │               │
                           StatefulSet      Does it need
                           (Databases,     Scale-to-Zero on
                           Kafka, ZK)      HTTP concurrency?
                                                ┌───────┴───────┐
                                                ▼               ▼
                                              (Yes)            (No)
                                                │               │
                                             Knative        Deployment
                                             Service      (Stateless APIs,
                                             (Serverless)  Web Services)
```

---

### 2. Comprehensive Workload Comparison Matrix

| Workload Controller | Lifecycle | Pod Identity | Storage Pattern | Scaling / Rollout Order | Primary Use Cases |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Deployment** | Continuous | Ephemeral, random hashes (`web-7d9f...`) | Shared stateless or ReadOnly | Concurrent RollingUpdate (`maxSurge`, `maxUnavailable`) | Stateless web apps, REST APIs, NGINX, microservices |
| **StatefulSet** | Continuous | Stable, ordinal names (`db-0`, `db-1`) | Dedicated PVC per replica (`volumeClaimTemplates`) | Sequential ordered rollout (`0 -> 1 -> 2`), reverse teardown | Relational databases (PostgreSQL, MySQL), Kafka, ZooKeeper, Redis Cluster |
| **DaemonSet** | Continuous | Bound to physical node (`1 pod/node`) | Node-local (`hostPath` / local disk) | RollingUpdate node-by-node across cluster | Node monitoring (`node-exporter`), log collectors (`fluentd`), network CNI (`cilium`, `kube-proxy`) |
| **Job** | Run-to-completion | Ephemeral, runs until Exit Code 0 | Ephemeral or temporary PVC | Parallelism & completion tracking, retry on failure (`backoffLimit`) | Database migrations, batch processing, one-time data backups, report rendering |
| **CronJob** | Scheduled periodic | Spawns a Job per schedule | Ephemeral or temporary PVC | Governed by `concurrencyPolicy` (`Allow`, `Forbid`, `Replace`) | Nightly backups, periodic reconciliation, periodic cache warmers, cleanup jobs |
| **Knative Service** | Request-driven serverless | Ephemeral, managed by revisions | Stateless | Scaled 0 $\leftrightarrow$ N based on HTTP concurrency, traffic splitting | Webhooks, bursty APIs, event-driven HTTP functions with zero idle cost |
| **KEDA ScaledJob** | Event-driven batch | Ephemeral, runs per queue backlog | Ephemeral | Dynamically spawns batch Jobs matching queue length | Heavy GPU tasks, video transcoding, ML model inference, asynchronous message queue jobs |

---

### 3. The 6-Question Workload Decision Framework

Ask these six questions in architecture review meetings:

#### Question 1: Is the process continuous or finite?
- **Finite (It starts, performs work, and terminates):** **DO NOT use a Deployment.** If a script terminates inside a Deployment, Kubernetes considers it a failure and restarts it endlessly in `CrashLoopBackOff`. Use a **Job** or **CronJob**.
- **Continuous (It listens on a port or loops forever):** Use a **Deployment**, **StatefulSet**, or **DaemonSet**.

#### Question 2: Does the application maintain persistent local state?
- **No (Stateless):** Multiple instances can read/write to the same shared database. Pods are completely interchangeable. $\rightarrow$ **Deployment**.
- **Yes (Stateful):** Each replica needs its own dedicated data directory that must survive pod crashes and restarts. $\rightarrow$ **StatefulSet**.

#### Question 3: Does each replica need a predictable, permanent network identity?
- In a cluster of 3 database replicas, node 1 must always be known as the primary leader and nodes 2 and 3 as replication followers.
- If a pod dies and reschedules, it **must keep its exact hostname** so peers can reconnect. $\rightarrow$ **StatefulSet** with a **Headless Service** (`clusterIP: None`).
- If any pod can handle any incoming request equally $\rightarrow$ **Deployment** with a standard **ClusterIP Service**.

#### Question 4: Must the pod run on *every* physical host in the cluster?
- If you are deploying an agent that collects metrics from the physical Linux kernel, physical hardware interfaces, or node log files (`/var/log`), exactly one copy must exist per machine. $\rightarrow$ **DaemonSet**.
- If you want high availability across nodes, but do not need every single node running an instance, use a **Deployment** with **Pod Anti-Affinity**.

#### Question 5: When the workload is idle, should it cost $0 in resource consumption?
- If an internal API or webhook only receives 10 requests a day, running an idle 24/7 Deployment wastes compute.
- Use **Knative Serving** to scale to **0 replicas** during idle periods and activate instantly upon incoming HTTP requests.

#### Question 6: Is scaling driven by CPU/RAM or by an external message queue backlog?
- If scaling workers based on **CPU/Memory** $\rightarrow$ **Deployment** + standard **HPA**.
- If scaling workers based on **RabbitMQ messages**, **Kafka consumer lag**, or **AWS SQS depth** $\rightarrow$ **Deployment** + **KEDA ScaledObject** (continuous consumers) or **KEDA ScaledJob** (batch processors).

---

### 4. Real-World Architecture Scenarios

#### Scenario A: Database Migrations (e.g., Flyway, Liquibase, Django Migrate)
- **Problem:** When rolling out a new version of an app, database schema migrations must run **once** before the new web pods accept traffic.
- **Wrong Choice:** Embedding migrations inside the web app container startup (if 5 replicas boot simultaneously, they race and lock the database).
- **Correct Choice:** 
  1. A Kubernetes **Job** triggered in the CI/CD pipeline before the Deployment update, OR
  2. An **Init Container** on a Deployment with replica count set to 1.

#### Scenario B: Redis Cache (Standalone vs. Redis Cluster)
- **Standalone Redis (Temporary Cache):** If data loss is acceptable and Redis is purely an ephemeral cache, a **Deployment** with `replicas: 1` and an `emptyDir` or persistent volume is sufficient.
- **Redis Cluster with Sharding & Sentinel:** Nodes require persistent cluster state (`nodes.conf`), dedicated storage per shard, and fixed cluster hostnames (`redis-0`, `redis-1`). $\rightarrow$ **StatefulSet**.

#### Scenario C: Video Transcoding & Machine Learning Inference
- **Problem:** Users upload 4K video files. Each file takes 10 minutes of heavy CPU/GPU processing to transcode.
- **Wrong Choice:** A Deployment with 5 static worker pods. If 100 videos are uploaded, the queue backs up; if 0 videos are uploaded, 5 expensive GPU pods sit idle.
- **Correct Choice:** **KEDA ScaledJob**. For every video message in the Redis list or SQS queue, KEDA dynamically launches an ephemeral Kubernetes **Job** that mounts the GPU, transcodes the video, uploads the result to S3, and terminates immediately.

#### Scenario D: Node Log Shipping (Fluentbit / Promtail)
- **Problem:** Collecting `/var/log/containers/*.log` from all host machines.
- **Correct Choice:** **DaemonSet**. It automatically runs on every node, mounts the host `/var/log` directory via `hostPath`, and forwards logs to Elasticsearch or Loki.

---

### 5. Common Anti-Patterns to Avoid

| Anti-Pattern | Why It Fails in Production | Correct Solution |
| :--- | :--- | :--- |
| **Running bare Pods (`kind: Pod`)** | Bare pods have no controller. If the node reboots or crashes, the pod is permanently deleted and **never rescheduled**. | Always wrap pods in a **Deployment**, **StatefulSet**, or **Job**. |
| **Databases in a Deployment with shared PVC** | Multiple pods writing to the same filesystem without cluster-aware locking causes **immediate database corruption**. | Use a **StatefulSet** with `volumeClaimTemplates` (1 dedicated PV per replica). |
| **Finite batch scripts in a Deployment** | The script runs to completion and exits (Exit 0). Kubelet restarts it endlessly, leading to CPU churn and duplicate execution. | Use a **Job** (`restartPolicy: OnFailure` or `Never`). |
| **CronJob without `concurrencyPolicy: Forbid`** | If a job takes 15 minutes to run but is scheduled every 5 minutes, runs overlap, causing database deadlocks and memory exhaustion. | Set `concurrencyPolicy: Forbid`. |
| **DaemonSet when Deployment with Anti-Affinity suffices** | In a 500-node cluster, a DaemonSet runs 500 pods even if your traffic only requires 5 pods. | Use a **Deployment** with `podAntiAffinity` on `topologyKey: kubernetes.io/hostname`. |
