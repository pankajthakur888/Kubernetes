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


---

## 6. Serverless & Event-Driven Autoscaling (Knative & KEDA)

**Q11: Explain the Knative Serving architecture and how Scale-to-Zero actually works under the hood.**
**A:** Standard Kubernetes HPA cannot scale a Deployment to 0 replicas without dropping incoming traffic. Knative achieves **Scale-to-Zero** through three core components:
1. **Activator**: When a service has 0 replicas, the Ingress points traffic directly to the Activator. The Activator acts as a temporary buffer: it holds incoming HTTP requests in memory and immediately signals the Autoscaler (KPA) to spin up a pod. Once the pod becomes Ready, the Activator proxies the buffered request to the pod and updates the Ingress routing table to bypass the Activator.
2. **Queue-Proxy Sidecar**: Injected into every Knative pod alongside the application container. It intercepts all incoming requests, tracks real-time concurrency metrics, enforces `containerConcurrency` limits, and sends metrics to the Autoscaler via websockets.
3. **Autoscaler (KPA)**: Evaluates metrics reported by the Queue-Proxy. If no requests are received during the stable window (default 60s), the Autoscaler instructs Kubernetes to scale the deployment down to 0 replicas and points the Ingress back to the Activator.

**Q12: Knative vs. KEDA vs. Standard HPA: When should an architect choose which?**
**A:** 
- **Standard HPA:** Best for long-running, predictable services where scaling is driven strictly by **CPU or Memory** consumption (e.g., computational microservices, databases) and minimum 1 replica is acceptable.
- **Knative Serving:** Best for **HTTP request-driven serverless** architectures, public REST APIs, and webhooks where you need:
  - True scale-to-zero during idle periods.
  - Native percentage-based traffic splitting (Canary 80/20 or Blue-Green rollouts).
  - Revision immutability.
- **KEDA (Kubernetes Event-driven Autoscaling):** Best for **asynchronous event/message processing** where scaling depends on external queue backlogs, Kafka consumer lags, database queries, or Cron schedules.
- **Combined Pattern:** Modern architectures often use **both**: Knative handles the public-facing HTTP API / webhook ingest layer (scaling 0 <-> N on request concurrency), which publishes jobs to a message queue (RabbitMQ / Kafka). KEDA then scales the backend worker fleet based on queue depth.

**Q13: How does KEDA scale a Deployment from 0 to 1 without violating the Kubernetes HPA constraint?**
**A:** Standard Kubernetes HPA cannot scale a resource from 0 to 1 because its algorithm calculates `desiredReplicas = ceil[currentReplicas * (currentMetricValue / desiredMetricValue)]`. When `currentReplicas == 0`, multiplying by zero always yields zero.
KEDA solves this with a **two-phase architecture**:
1. **Scale 0 → 1 (Activation Phase):** The **KEDA Operator** directly monitors the external event source (e.g., RabbitMQ queue). When the queue backlog > 0, KEDA bypasses the HPA and directly patches the Deployment's `spec.replicas` from 0 to 1.
2. **Scale 1 ↔ N (Horizontal Scaling Phase):** Once at least 1 pod is running, the **KEDA Metrics API Server** exposes the queue depth to the standard Kubernetes External Metrics API (`external.metrics.k8s.io`). The built-in HPA controller consumes these metrics and handles all scaling between 1 and `maxReplicaCount`.
3. **Scale 1 → 0 (Deactivation Phase):** When the queue reaches 0 and the cooldown period expires, KEDA scales the Deployment back down to 0 and pauses HPA evaluations.

**Q14: What causes "Cold Starts" in Knative, and what architectural strategies do you use to mitigate them in production?**
**A:** A cold start is the latency penalty incurred when a request arrives while replicas = 0. The latency is the cumulative time of:
1. Ingress routing to Activator.
2. Scheduler placing the pod on a node.
3. CRI pulling the container image (if not cached).
4. Container startup and application runtime initialization (JVM, Python interpreter, DB connection pools).
5. Readiness probe passing.

**Production Mitigation Strategies:**
1. **Set `minScale: 1` on critical paths:** If an API has strict SLA (< 100ms), set `autoscaling.knative.dev/min-scale: "1"` to keep 1 warm pod while retaining Knative's automated revisions and canary routing.
2. **Compile to Native Binaries:** For Java workloads, use GraalVM Native Image (Quarkus/Micronaut) to drop boot time from 6 seconds to 30 milliseconds. For Go/Rust, compile statically linked small images (< 15MB).
3. **Tune `scale-to-zero-pod-retention-period`:** Extend the idle retention window (e.g., 5-10 minutes) so pods stay warm between intermittent requests.
4. **Use Image Pre-pulling / DaemonSets:** Pre-pull base images on all worker nodes to eliminate image download time.

**Q15: What is the architectural difference between KEDA `ScaledObject` and `ScaledJob`, and what happens if you manually define an HPA alongside a `ScaledObject`?**
**A:** 
- **`ScaledObject`:** Targets long-lived workloads (Deployments, StatefulSets). Pods remain running continuously, pulling messages from a queue in an active loop. Best for stream processing, high throughput, and low-latency message consumers.
- **`ScaledJob`:** Targets ephemeral, run-to-completion workloads (Kubernetes `Job`). KEDA spins up an isolated Job pod for each item or batch in the queue. The pod runs, processes the payload, and terminates. Best for heavy, isolated tasks (video transcoding, batch PDF generation, machine learning training).
- **The Dual-HPA Conflict Gotcha:** When you define a `ScaledObject`, KEDA automatically creates and owns an HPA object named `keda-hpa-<name>`. If an engineer also commits a manual `HorizontalPodAutoscaler` pointing to the same deployment, **both controllers will fight**: KEDA will try to scale based on queue length while the standard HPA tries to scale based on CPU/RAM, leading to constant replica flapping and unstable production deployments.
