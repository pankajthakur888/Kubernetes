# Certified Kubernetes Administrator (CKA) Preparation Q&A

This guide aligns with the 14-phase CKA Preparation Roadmap. All scenarios are heavily practical, reflecting the command-line nature of the actual CKA exam.

---

## Phase 1: Kubernetes Architecture & Core Concepts
**Q: How do you verify the health and status of the core control plane components?**
**A:** Since `kubectl get componentstatuses` is deprecated, the modern approach is to check the `kube-system` static pods:
```bash
kubectl get pods -n kube-system -l tier=control-plane
```
For deep component troubleshooting, log into the control plane and check the Kubelet managing them:
```bash
sudo journalctl -u kubelet -f
```

---

## Phase 2: Pods, Deployments, ReplicaSets
**Q: Create a deployment named `web-app` using the `nginx:1.19` image with 3 replicas. After creation, scale it up to 5 replicas.**
**A:** Use imperative commands for speed:
```bash
kubectl create deployment web-app --image=nginx:1.19 --replicas=3
kubectl scale deployment web-app --replicas=5
```

---

## Phase 3: Services & Networking
**Q: Expose the `web-app` deployment created above as a NodePort service on the specific NodePort `30080`.**
**A:** First, expose it imperatively, but you must output to YAML to set the exact NodePort:
```bash
kubectl create service nodeport web-app-svc --tcp=80:80 --node-port=30080
```
*(Note: As of modern kubectl versions, `--node-port` is available natively in `create service nodeport`!)*

---

## Phase 4: ConfigMaps & Secrets
**Q: Create a ConfigMap named `app-config` with a literal value `ENV=prod`. Create a pod named `config-tester` (image `busybox:1.28`, command `sleep 3600`) and mount this ConfigMap at `/etc/config`.**
**A:** 
```bash
kubectl create configmap app-config --from-literal=ENV=prod
kubectl run config-tester --image=busybox:1.28 --dry-run=client -o yaml -- sleep 3600 > pod.yaml
```
Edit `pod.yaml`:
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: config-tester
spec:
  containers:
  - image: busybox:1.28
    name: config-tester
    command: ["sleep", "3600"]
    volumeMounts:
    - name: config-vol
      mountPath: /etc/config
  volumes:
  - name: config-vol
    configMap:
      name: app-config
```
```bash
kubectl apply -f pod.yaml
```

---

## Phase 5: Storage, PV, PVC, StorageClass
**Q: Create a PersistentVolume `data-pv` (1Gi, hostPath `/data`, accessMode `ReadWriteOnce`). Create a PersistentVolumeClaim `data-pvc` (500Mi) that binds to it.**
**A:** PVs must be created via YAML:
```yaml
# pv.yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: data-pv
spec:
  capacity:
    storage: 1Gi
  accessModes:
    - ReadWriteOnce
  hostPath:
    path: "/data"
```
```yaml
# pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: data-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 500Mi
```
```bash
kubectl apply -f pv.yaml -f pvc.yaml
```

---

## Phase 6: Scheduling, Taints, Tolerations, Affinity
**Q: Taint node `worker1` with `env=prod:NoSchedule`. Create a pod named `prod-pod` using image `nginx` that can be scheduled on this node.**
**A:**
```bash
kubectl taint nodes worker1 env=prod:NoSchedule
kubectl run prod-pod --image=nginx --dry-run=client -o yaml > prod-pod.yaml
```
Edit `prod-pod.yaml` and add tolerations to the `spec`:
```yaml
spec:
  tolerations:
  - key: "env"
    operator: "Equal"
    value: "prod"
    effect: "NoSchedule"
```

---

## Phase 7: RBAC & Security
**Q: Create a ServiceAccount `dev-sa`. Create a Role `dev-role` that can only `list` and `get` pods in the `default` namespace. Bind them using a RoleBinding `dev-binding`.**
**A:**
```bash
kubectl create sa dev-sa
kubectl create role dev-role --verb=get,list --resource=pods
kubectl create rolebinding dev-binding --role=dev-role --serviceaccount=default:dev-sa
```

---

## Phase 8: Ingress & Gateway concepts
**Q: Create an Ingress resource `app-ingress` that routes traffic for `app.local` to the service `web-app-svc` on port 80.**
**A:**
```bash
kubectl create ingress app-ingress --rule="app.local/*=web-app-svc:80"
```

---

## Phase 9: Helm & Application Management
**Q: View all releases in all namespaces using Helm.**
**A:**
```bash
helm list --all-namespaces
```

---

## Phase 10: Troubleshooting
**Q: A pod named `db-app` is in `CrashLoopBackOff`. How do you investigate?**
**A:**
1. Check events to see if it's failing scheduling, pulling images, or OOMKilled: 
   `kubectl describe pod db-app`
2. Check logs of the current crashing container: 
   `kubectl logs db-app`
3. Check logs of the *previous* failed container instance: 
   `kubectl logs db-app --previous`

---

## Phase 11: Cluster Maintenance & Upgrades
**Q: Safely drain `worker2` for maintenance without getting stuck on daemonsets or local data.**
**A:**
```bash
kubectl drain worker2 --ignore-daemonsets --delete-emptydir-data --force
```

---

## Phase 12: ETCD backup/restore
**Q: Take a snapshot of the local ETCD cluster and save it to `/var/lib/etcd-backup.db`.**
**A:** 
```bash
ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379   --cacert=/etc/kubernetes/pki/etcd/ca.crt   --cert=/etc/kubernetes/pki/etcd/server.crt   --key=/etc/kubernetes/pki/etcd/server.key   snapshot save /var/lib/etcd-backup.db
```

---

## Phase 13: Advanced kubectl (JSONPath / Custom Columns)
**Q: List all pods showing their name, the node they run on, and their node IP using custom columns.**
**A:**
```bash
kubectl get pods -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName,IP:.status.hostIP
```
**Q: Find the node with the highest CPU capacity using JSONPath.**
**A:**
```bash
kubectl get nodes -o jsonpath='{.items[*].status.capacity.cpu}'
```

---

## Phase 14: Full CKA Mock Exams
**Q: How can I practice a full real-world scenario?**
**A:** Run the included mock scenario script inside this repository on your live K8s or K3s cluster:
```bash
./cka-lab-scenario.sh
```
This deploys an intentionally broken environment (NetworkPolicies) for you to troubleshoot and fix, simulating exact exam conditions!
