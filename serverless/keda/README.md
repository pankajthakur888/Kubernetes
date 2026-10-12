# KEDA Deep Dive: Kubernetes Event-Driven Autoscaling

KEDA (Kubernetes Event-driven Autoscaling) is a lightweight CNCF graduated component that brings event-driven autoscaling to Kubernetes. It allows application workloads to scale from **0 to N** replicas based on external event metrics (message queues, databases, streaming pipelines, Prometheus queries, and schedules).

---

## 1. Why KEDA? The Problem with Standard Kubernetes HPA

The standard Kubernetes Horizontal Pod Autoscaler (HPA) has two major limitations in production:

1. **No Scale-to-Zero**: HPA requires `minReplicas ≥ 1`. Even when a queue is completely empty for weeks, at least one pod must remain active, consuming idle cluster resources.
2. **Resource Metrics Only**: HPA natively only understands Pod CPU and Memory utilization. If 100,000 messages arrive in a RabbitMQ queue or Kafka topic, CPU usage might remain at 5% while the queue explodes. HPA cannot react until the single consumer pod becomes CPU-pegged.

```text
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                                   THE KEDA BRIDGE                                      │
├────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                        │
│     [ RabbitMQ / Kafka / AWS SQS / Redis / Cron / Prometheus ]                         │
│                                │                                                       │
│                                ▼ (KEDA Scaler polls metric)                            │
│                        ┌──────────────┐                                                │
│                        │ KEDA Operator│                                                │
│                        └───────┬──────┘                                                │
│                                │                                                       │
│             ┌──────────────────┴──────────────────┐                                    │
│             ▼ (When metric = 0 or 0 -> 1)         ▼ (When metric > 1)                  │
│       Scale 0 <-> 1 Direct Activation         External Metrics API                     │
│       (Bypasses standard HPA)                 (Feeds metric to HPA)                    │
│             │                                     │                                    │
│             ▼                                     ▼                                    │
│     [ Deployment (0 <-> 1) ]             [ Standard K8s HPA Controller ]               │
│                                                   │                                    │
│                                                   ▼                                    │
│                                          Scales Deployment 1 <-> N                     │
└────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. KEDA Architecture & Core Components

KEDA consists of three micro-services in the `keda` namespace:

1. **KEDA Operator**:
   - Controller that watches `ScaledObject` and `ScaledJob` custom resources.
   - Responsible for **Scale-to-Zero** (scaling Deployment to 0 when queue is empty) and **Activation** (scaling 0 → 1 when an event arrives).
   - Generates and manages the underlying Kubernetes `HorizontalPodAutoscaler` resource.
2. **KEDA Metrics API Server**:
   - Implements the Kubernetes External Metrics API (`external.metrics.k8s.io`).
   - Translates metrics from 60+ external systems into a format that the Kubernetes HPA controller can consume for scaling between 1 and N replicas.
3. **KEDA Admission Webhooks**:
   - Validates configuration syntax of `ScaledObject` and `TriggerAuthentication` specifications.

---

## 3. Core CRDs: ScaledObject vs. ScaledJob

KEDA provides two primary custom resources:

### A. ScaledObject
Targets a **long-running Deployment or StatefulSet**. Workers stay running and process events in a loop.
- **Scale Range**: Typically `minReplicaCount: 0` to `maxReplicaCount: 50`.
- **Ideal For**: Continuous event processors (e.g., Celery consumers, RabbitMQ workers, Kafka consumer groups).

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: rabbitmq-consumer-scaler
spec:
  scaleTargetRef:
    name: order-processor-deployment
  minReplicaCount: 0
  maxReplicaCount: 30
  pollingInterval: 15
  cooldownPeriod: 60
  triggers:
    - type: rabbitmq
      metadata:
        queueName: orders
        mode: QueueLength
        value: "20" # 1 pod per 20 queued messages
```

### B. ScaledJob
Targets a **Kubernetes Job**. Launches an ephemeral, run-to-completion Pod for each batch of messages. Once a Job finishes, its pod terminates.
- **Scale Range**: Launches 0 to `maxReplicaCount` Jobs.
- **Ideal For**: Heavy batch workloads, video transcoding, PDF generation, machine learning inference jobs where workers should not run as long-lived daemons.

---

## 4. Popular Built-In Scalers (60+ Supported)

| Scaler Category | Supported Technologies | Example Trigger Metric |
| :--- | :--- | :--- |
| **Message Queues** | RabbitMQ, AWS SQS, Azure Service Bus, GCP PubSub | Queue backlog count |
| **Streaming** | Apache Kafka, AWS Kinesis, Azure Event Hubs | Consumer group lag |
| **Databases** | PostgreSQL, MySQL, Redis, MongoDB | Custom SQL query result |
| **Monitoring** | Prometheus, Datadog, New Relic, AWS CloudWatch | PromQL query result |
| **Scheduling** | Cron | Time-of-day / Day-of-week |
| **Cloud Services** | AWS DynamoDB Streams, Azure Blob, GCP Cloud Storage | Item count / Storage events |

---

## 5. Production Best Practices & Common Gotchas

### ⚠️ Never Create a Manual HPA for a ScaledObject
When you apply a `ScaledObject`, KEDA **automatically creates and controls** an HPA named `keda-hpa-<scaledobject-name>`. 
If you also define a manual `HorizontalPodAutoscaler` in your Helm chart pointing to the same Deployment, both controllers will fight each other in an infinite scaling loop.

### ⏱️ Tuning `pollingInterval` and `cooldownPeriod`
- `pollingInterval` (Default 30s): How frequently KEDA checks the queue depth. Lower this to `5s-10s` for high-throughput, low-latency queues.
- `cooldownPeriod` (Default 300s): How long KEDA waits with 0 queue messages before scaling pods down to 0. Keeps pods warm to avoid thrashing if messages arrive sporadically.

### 🔐 Secure Credentials with `TriggerAuthentication`
Never hardcode passwords or connection strings in the `ScaledObject`. Use `TriggerAuthentication` to reference a Kubernetes Secret or HashiCorp Vault.

---

## 6. Hands-on Manifests

| Manifest | Purpose |
| :--- | :--- |
| [01-scaledobject-cron.yaml](file:///Ubuntu/opt/myproject/kubernetes/serverless/keda/manifests/01-scaledobject-cron.yaml) | Scheduled autoscaling (business hours scale-up 08:00–18:00, scale-to-zero nights/weekends) |
| [02-scaledobject-rabbitmq.yaml](file:///Ubuntu/opt/myproject/kubernetes/serverless/keda/manifests/02-scaledobject-rabbitmq.yaml) | Real-world queue scaler (1 pod per 10 messages, scale 0 to 20 replicas) with Secret authentication |
| [03-scaledjob-batch.yaml](file:///Ubuntu/opt/myproject/kubernetes/serverless/keda/manifests/03-scaledjob-batch.yaml) | Batch processing ScaledJob that triggers run-to-completion batch jobs per message backlog |

---

## 7. Quickstart: Installation

To install KEDA Operator on your cluster:

```bash
cd /opt/myproject/kubernetes/serverless/keda
chmod +x install-keda.sh
sudo ./install-keda.sh
```

Verify KEDA CRDs and Operator pods:
```bash
kubectl get pods -n keda
kubectl get customresourcedefinitions | grep keda
```
