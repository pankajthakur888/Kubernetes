# Knative & KEDA: Serverless and Event-Driven Autoscaling on Kubernetes

This module provides comprehensive architecture guides, hands-on manifests, and installation automation for **Knative** (Serverless workloads, scale-to-zero, traffic splitting) and **KEDA** (Kubernetes Event-driven Autoscaling for message queues, databases, and cron schedules).

---

## 1. Architectural Comparison: HPA vs. KEDA vs. Knative

Kubernetes out-of-the-box Horizontal Pod Autoscaler (HPA) was built primarily around resource metrics (CPU and Memory). Modern cloud-native architectures require reacting to **HTTP request volume, message queues, Kafka lags, and external events**.

```text
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                                 AUTOSCALING SPECTRUM                                   │
├──────────────────────────┬─────────────────────────────┬───────────────────────────────┤
│    Standard HPA          │           KEDA              │           Knative             │
├──────────────────────────┼─────────────────────────────┼───────────────────────────────┤
│ • Scales on CPU/RAM      │ • Scales on 60+ external    │ • Scales on HTTP request rate │
│ • Cannot scale to 0      │   event sources (Kafka, SQS,│   and concurrent connections  │
│   (Minimum 1 replica)    │   RabbitMQ, Prometheus)     │ • True Scale-to-Zero (0 <-> N)│
│ • Reactive (lags behind  │ • Scales 0 <-> N            │ • Integrated Ingress & Routing│
│   traffic surges)        │ • Bridges events into HPA   │ • Canary traffic splitting    │
│ • No traffic management  │ • Supports batch Jobs       │ • Revision immutability       │
└──────────────────────────┴─────────────────────────────┴───────────────────────────────┘
```

### Detailed Feature Matrix

| Feature | Standard Kubernetes HPA | KEDA (Event-Driven) | Knative Serving (Serverless) |
| :--- | :--- | :--- | :--- |
| **Primary Trigger** | CPU / Memory metrics | External events (Queues, DBs, Cron) | HTTP requests / Concurrency |
| **Scale-to-Zero (0 replicas)** | ❌ No (minReplicas ≥ 1) | ✅ Yes (activates 0 → 1) | ✅ Yes (activates 0 → 1) |
| **Autoscaler Engine** | K8s HPA Controller | KEDA Operator + External Metrics API | Knative Pod Autoscaler (KPA) / HPA |
| **Traffic Management** | Ingress controller needed | Ingress controller needed | Built-in (Envoy / Kourier / Istio) |
| **Canary / Traffic Splitting** | Requires Service Mesh / Ingress | Requires Service Mesh / Ingress | Built-in (e.g. 80% v1, 20% v2) |
| **Batch Workload Scaling** | ❌ Deployments/StatefulSets only| ✅ Yes (`ScaledJob` runs run-to-finish) | ❌ Request-driven only |
| **Cold Start Latency** | None (always ≥ 1 pod) | Minimal (pod pull & boot) | 200ms - 2s depending on runtime |
| **Best Used For** | Continuous background pods | Async workers, consumers, cron batch | Webhooks, REST APIs, microservices |

---

## 2. Knative Architecture: Scale-to-Zero & Traffic Management

Knative consists of two main pillars:
1. **Knative Serving**: Manages stateless request-driven workloads with automated revisions, traffic routing, and rapid scale-to-zero.
2. **Knative Eventing**: Decoupled, asynchronous event-driven architecture using CloudEvents, Brokers, Triggers, and Channels.

### The Knative Scale-to-Zero Lifecycle

```text
[HTTP Client] 
      │ (Traffic arrives)
      ▼
┌──────────────┐
│ Ingress / LB │
└──────┬───────┘
       │
       ▼
┌────────────────────────────────────────────────────────┐
│ When Replicas = 0:                                     │
│ Ingress routes request to the ACTIVATOR.               │
│                                                        │
│ 1. Activator buffers incoming HTTP requests in memory. │
│ 2. Activator notifies the AUTOSCALER (KPA).            │
│ 3. Autoscaler scales Deployment from 0 -> 1.           │
│ 4. Once Pod is ready, Activator proxies traffic to it. │
└──────────────────────┬─────────────────────────────────┘
                       │
                       ▼
┌────────────────────────────────────────────────────────┐
│ When Replicas >= 1:                                    │
│ Ingress routes directly to Pod's QUEUE-PROXY sidecar.  │
│                                                        │
│ • Queue-Proxy enforces containerConcurrency.           │
│ • Queue-Proxy reports real-time metrics to Autoscaler. │
│ • If idle for stable-window (60s), scales to 0.        │
└────────────────────────────────────────────────────────┘
```

Explore manifests and deep dive: [knative/README.md](file:///Ubuntu/opt/myproject/kubernetes/serverless/knative/README.md)

---

## 3. KEDA Architecture: Event-Driven Metrics & Scaling

KEDA acts as a lightweight event metrics adapter that plugs directly into standard Kubernetes HPA without reinventing cluster orchestration.

### How KEDA Works Internally

```text
┌─────────────────┐       Polls Event Source (e.g., RabbitMQ queue length)
│  External Event │ ◄───────────────────────────────────────────────────────┐
│     Source      │                                                         │
└─────────────────┘                                                         │
                                                                            │
┌───────────────────────────────────────────────────────────────────────────┴────┐
│ KEDA Operator                                                                  │
│                                                                                │
│  1. When queue length == 0:                                                    │
│     KEDA scales Deployment down to 0 replicas.                                 │
│     KEDA pauses the HPA.                                                       │
│                                                                                │
│  2. When queue length > 0:                                                     │
│     KEDA activates Deployment (scales 0 -> 1).                                 │
│     KEDA unpauses HPA and exposes custom metrics via KEDA Metrics Server.      │
│                                                                                │
│  3. When scaling 1 <-> N:                                                      │
│     Standard Kubernetes HPA reads metrics from KEDA Metrics Server and scales. │
└────────────────────────────────────────────────────────────────────────────────┘
```

Explore manifests and deep dive: [keda/README.md](file:///Ubuntu/opt/myproject/kubernetes/serverless/keda/README.md)

---

## 4. When to Use Knative vs. KEDA

```text
                              Workload Architecture Decision Tree
                                               │
                                 Is your workload HTTP or Event/Queue?
                                  ┌────────────┴────────────┐
                                  ▼                         ▼
                            [ HTTP-Driven ]           [ Event / Queue ]
                                  │                         │
                     Do you need scale-to-zero,             │
                     traffic splitting, or revisions?       ▼
                        ┌─────────┴─────────┐       Do tasks process streaming queues,
                        ▼                   ▼       Kafka lags, or cron schedules?
                   ( Yes )                ( No )            │
                      │                     │          ┌────┴────┐
                      ▼                     ▼          ▼         ▼
                 Use Knative            Standard    ( Continuous ) ( Batch Jobs )
                   Serving             Deployment       │               │
                                       + Ingress        ▼               ▼
                                                  KEDA ScaledObject  KEDA ScaledJob
```

### Can You Use Both Together?
**Yes! In modern production systems, they solve complementary problems:**
- **Knative Serving**: Handles the public **Ingress / REST API / Webhooks** layer (instant autoscaling, canary traffic splits, zero idle cost).
- **KEDA**: Handles the **Backend asynchronous worker pools** (scaling Celery/RabbitMQ consumers, Kafka stream processors, and SQS batch jobs based on backlog depth).

---

## 5. Directory Layout

```text
serverless/
├── README.md                      # This master comparison & architecture guide
├── knative/
│   ├── README.md                  # Knative Serving & Eventing deep dive
│   ├── install-knative.sh         # Automated installer for Knative + Kourier
│   └── manifests/
│       ├── 01-hello-service.yaml  # Knative Service with scale-to-zero and concurrency
│       ├── 02-traffic-split.yaml  # Blue-green and canary traffic splitting (80/20)
│       └── 03-eventing-ping.yaml  # CloudEvents PingSource to Sink Service
└── keda/
    ├── README.md                  # KEDA ScaledObject, ScaledJob & Scalers guide
    ├── install-keda.sh            # Automated installer for KEDA Operator via Helm
    └── manifests/
        ├── 01-scaledobject-cron.yaml      # Cron/Schedule scaler with timezone
        ├── 02-scaledobject-rabbitmq.yaml  # RabbitMQ queue depth scaler (0 -> N)
        └── 03-scaledjob-batch.yaml        # ScaledJob for processing message batches
```
