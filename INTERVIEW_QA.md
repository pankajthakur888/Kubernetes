# Advanced Kubernetes Interview Q&A (Deep Dive)

This document contains advanced, scenario-based, and architectural questions typically asked in Senior/Lead Kubernetes Engineer or DevOps interviews.

---

## 1. Architecture & Core Components

**Q1: Walk me through exactly what happens when you run `kubectl run nginx --image=nginx`.**
**A:** 
1. **kubectl** validates the request and converts it into a JSON payload. It authenticates with the **API Server** (via TLS/kubeconfig) and sends a POST request.
2. **API Server** authenticates and authorizes the request (RBAC), runs Admission Controllers (e.g., Mutating/Validating Webhooks), and writes the Pod definition to **etcd**.
3. **etcd** sends a notification back to the API Server that the state has changed.
4. The **kube-scheduler** (watching the API Server for unassigned pods) notices the new Pod. It runs filtering (resource limits, node selectors) and scoring algorithms to pick the best node, then binds the Pod to that node by updating the API Server.
5. The **kubelet** on the assigned node (also watching the API Server) sees the Pod bound to its node. It talks to the **Container Runtime Interface (CRI)** (like containerd) to pull the image and start the container, and the **Container Network Interface (CNI)** (like Cilium/Calico) to allocate an IP and setup networking.
6. The kubelet reports the Pod status back to the API Server, which updates etcd.

**Q2: What is the difference between a Deployment and a StatefulSet, and when would you use each?**
**A:** 
- **Deployment:** Best for stateless applications. Pods are identical and interchangeable. They are given random hashes in their names (e.g., `web-5f89c...`). If a pod dies, a new one spins up anywhere.
- **StatefulSet:** Best for stateful applications (databases, Kafka, ZooKeeper). It provides:
  - **Sticky Identity:** Pods get predictable, ordinal names (`db-0`, `db-1`).
  - **Ordered Deployment/Scaling:** `db-1` won't start until `db-0` is ready.
  - **Stable Storage:** Each replica gets its own PersistentVolumeClaim (via `volumeClaimTemplates`). If `db-0` dies and is rescheduled, it automatically reattaches to the exact same PersistentVolume.

---

## 2. Networking (CNI, Services, Ingress)

**Q3: How does a Kubernetes Service (ClusterIP) actually route traffic to Pods under the hood?**
**A:** The API Server assigns a virtual IP (ClusterIP) to the Service. The **kube-proxy** daemon running on every node watches for Services and Endpoints. 
- In **iptables mode** (legacy/default), kube-proxy writes iptables rules that intercept traffic destined for the ClusterIP and DNATs (Destination NAT) it to one of the healthy Pod IPs (using statistical round-robin).
- In **IPVS mode**, it creates virtual servers in the Linux kernel for better performance at scale.
- If using an advanced CNI like **Cilium (eBPF)**, kube-proxy can actually be bypassed entirely (kube-proxy replacement). Cilium writes eBPF programs directly into the Linux kernel socket layer, routing traffic at the packet level with zero iptables overhead.

**Q4: You mentioned Cilium and eBPF. Why is eBPF replacing iptables in modern Kubernetes networking?**
**A:** `iptables` evaluates rules sequentially (O(N)). In a cluster with thousands of services and network policies, iptables chains become massively long, causing severe CPU overhead and latency just to route a packet. 
**eBPF** (Extended Berkeley Packet Filter) allows running sandboxed programs directly in the kernel space. It uses hash tables (O(1) lookups) regardless of cluster size. It provides significantly lower network latency, higher throughput, and deep observability (L7 visibility) without sidecar proxies.

---

## 3. Advanced Scheduling

**Q5: What is the difference between Node Affinity and Taints/Tolerations?**
**A:** They are opposites that are often used together:
- **Node Affinity (Pod property):** Attracts Pods to specific Nodes. (e.g., "This Pod *must* run on a node with a GPU").
- **Taints (Node property) & Tolerations (Pod property):** Repels Pods from Nodes. A tainted node says "No pod can schedule here unless it has a matching toleration" (e.g., "This node is dedicated to the billing team").
- **Use case:** To dedicate a node to a specific app, you apply a Taint to the node (so random pods stay away) AND Node Affinity to the app's pods (so they actively seek out that node).

**Q6: What happens if a Pod's memory limit is lower than its memory request?**
**A:** Kubernetes will reject the Pod manifest during API validation. Requests must be less than or equal to Limits.
- **Request:** What the scheduler uses to find a node with enough capacity. It is guaranteed.
- **Limit:** The hard cap. If a container exceeds its Memory Limit, the Linux kernel (OOM Killer) terminates it (`OOMKilled`). If it exceeds its CPU limit, it gets throttled, but not killed.

---

## 4. Troubleshooting & Production Issues

**Q7: An application pod keeps crashing with `OOMKilled`. However, when you check the host node, it has plenty of free RAM. Why?**
**A:** `OOMKilled` (Exit Code 137) means the container exceeded the *Memory Limit* specified in its Pod spec (the cgroup limit), not the physical memory of the host node. To fix this, you must analyze the application for memory leaks, or if the workload genuinely requires more memory, increase the `resources.limits.memory` in the deployment YAML.

**Q8: DNS resolution is failing sporadically inside your cluster (e.g., 5% of requests to `service.namespace.svc.cluster.local` timeout). How do you debug this?**
**A:** This is a classic DNS scaling/concurrency issue.
1. Check **CoreDNS logs**: `kubectl logs -n kube-system -l k8s-app=kube-dns`. Look for rate-limiting or crash loops.
2. **Conntrack table limits:** In high-traffic clusters, the Linux `conntrack` table might be filling up, dropping UDP packets. (Run `dmesg | grep conntrack` on the node).
3. **ndots:5 issue:** By default, Kubernetes pods append multiple search domains for every DNS lookup. A single query for `google.com` might result in 5+ queries to CoreDNS.
**Fixes:** Use `NodeLocal DNSCache` (runs a lightweight DNS cache as a DaemonSet on every node) to offload TCP/UDP traffic, or reduce the `ndots` value in the Pod's `dnsConfig`.

**Q9: A worker node goes `NotReady`. Describe your troubleshooting steps.**
**A:**
1. `kubectl describe node <name>` - Check the conditions (DiskPressure, MemoryPressure, PIDPressure).
2. SSH into the node and check the kubelet status: `systemctl status kubelet` and `journalctl -u kubelet -f`.
3. Check if the Container Runtime is hung: `systemctl status containerd` or run `crictl ps`.
4. Check disk space: `df -h` (If `/var/lib/containerd` or `/var/lib/kubelet` is 100% full, the kubelet will mark the node `NotReady` and trigger eviction).
5. Check for expired certificates in `/var/lib/kubelet/pki/`.

---

## 5. Security

**Q10: How do you restrict a pod from running as the root user?**
**A:** You enforce this at two levels:
1. **Pod level (SecurityContext):** 
```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
```
2. **Cluster level (Admission Control):** Implement a Pod Security Admission (PSA) standard of `Restricted`, or use a policy engine like OPA Gatekeeper or Kyverno to block any Pod manifest that doesn't explicitly set `runAsNonRoot: true`.
