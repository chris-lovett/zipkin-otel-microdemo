# OpenShift Monitoring Configuration Fix

## Problem Discovered
The ServiceMonitor was created but Prometheus wasn't discovering it because the `tracing-demo` namespace was missing the required label for OpenShift user workload monitoring.

## Root Cause
In OpenShift, namespaces must be explicitly labeled to enable monitoring by the user-workload Prometheus instance. Without this label, ServiceMonitors in the namespace are ignored.

## Solution Applied

### Step 1: Enable User Workload Monitoring for Namespace
```bash
kubectl label namespace tracing-demo openshift.io/user-monitoring=true
```

**IMPORTANT**: The correct label is `openshift.io/user-monitoring=true`, NOT `openshift.io/cluster-monitoring=true`. The user-workload Prometheus is configured to EXCLUDE namespaces with the cluster-monitoring label.

### Step 2: Label the ServiceMonitor
```bash
kubectl label servicemonitor -n tracing-demo consul-mesh-metrics openshift.io/user-monitoring=true
```

**CRITICAL**: Both the namespace AND the ServiceMonitor itself must have the `openshift.io/user-monitoring` label. The Prometheus Operator uses `serviceMonitorSelector` to filter which ServiceMonitors to process.

These labels tell OpenShift's user-workload Prometheus Operator to:
1. Watch for ServiceMonitors in this namespace
2. Process ServiceMonitors with the matching label
3. Generate scrape configurations for discovered ServiceMonitors
4. Add the targets to Prometheus

### Step 2: Verify Configuration
After applying the label, Prometheus should automatically:
- Discover the `consul-mesh-metrics` ServiceMonitor
- Create scrape jobs for all 7 endpoints (one per pod)
- Start scraping metrics from `http://<pod-ip>:9090/federate`

### Expected Result
Within 20-30 seconds, Prometheus targets should show:
- 7 new targets for port 9090 in tracing-demo namespace
- Health status: "up"
- Scrape URLs pointing to pod IPs on port 9090

## OpenShift Monitoring Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ OpenShift Cluster                                           │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ openshift-monitoring namespace                       │  │
│  │  - Cluster Prometheus (monitors platform)            │  │
│  │  - Prometheus Operator                               │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ openshift-user-workload-monitoring namespace         │  │
│  │  - User Workload Prometheus (monitors apps)          │  │
│  │  - Prometheus Operator                               │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ tracing-demo namespace                               │  │
│  │  (needs label: openshift.io/cluster-monitoring=true)│  │
│  │                                                       │  │
│  │  - ServiceMonitor: consul-mesh-metrics               │  │
│  │  - Service: consul-mesh-metrics (headless)           │  │
│  │  - Pods with prometheus-sidecar on port 9090         │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

## Key Differences from Standard Kubernetes

### Standard Kubernetes
- Single Prometheus Operator watches all namespaces
- ServiceMonitors work immediately after creation

### OpenShift
- Two Prometheus instances: cluster and user-workload
- Namespaces must be labeled for user-workload monitoring
- Label: `openshift.io/cluster-monitoring=true`

## Verification Commands

```bash
# Check namespace label
kubectl get namespace tracing-demo -o yaml | grep openshift.io/user-monitoring

# Check ServiceMonitor
kubectl get servicemonitor -n tracing-demo

# Check Service endpoints
kubectl get endpoints -n tracing-demo consul-mesh-metrics

# Check Prometheus targets (after port-forward to Prometheus)
curl -s 'http://localhost:9090/api/v1/targets' | \
  jq '.data.activeTargets[] | select(.labels.namespace=="tracing-demo")'
```

## Timeline
1. **Initial Issue**: Metrics endpoint returns nothing (port 20200 binds to localhost)
2. **Solution**: Implemented Prometheus sidecar pattern
3. **ServiceMonitor Created**: But no targets appeared in Prometheus
4. **Root Cause Found**: Missing namespace label for OpenShift monitoring
5. **Fix Applied**: Added `openshift.io/cluster-monitoring=true` label
6. **Expected**: Prometheus discovers targets within 20-30 seconds

## Next Steps
Once targets appear as "up":
1. Query metrics: `envoy_cluster_upstream_rq_total{namespace="tracing-demo"}`
2. Verify Consul UI shows metrics
3. Check Grafana dashboards
4. Generate traffic with load test
5. Document complete solution