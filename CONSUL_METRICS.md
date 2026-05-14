# Configuring Consul UI Metrics with Prometheus

## Overview

The Consul UI can display service metrics (request rates, error rates, latency) from Prometheus. If the metrics section is empty despite running load tests, it means Consul UI isn't properly configured to query Prometheus.

## Prerequisites

- Prometheus deployed and running
- Consul Service Mesh with Envoy sidecars
- Envoy sidecars exposing metrics on port 20200

## Architecture

```
Consul UI (Browser)
    ↓ (queries)
Consul Server (metrics proxy)
    ↓ (queries)
Prometheus
    ↓ (scrapes)
Envoy Sidecars (port 20200/metrics)
```

## Step 1: Run Diagnostics

First, identify what's missing:

```bash
cd /Users/chrislovett/hashi/monitoring/tracing/zipkin-otel-microdemo
./diagnose-consul-metrics.sh
```

This will check:
1. Consul UI configuration
2. Prometheus deployment
3. Prometheus service
4. Envoy metrics endpoints
5. Prometheus scrape configuration
6. ServiceMonitor CRDs

## Step 2: Configure Consul UI for Metrics

### Option A: Using Helm Values (Recommended)

Create or update your Consul Helm values file (`consul-values.yaml`):

```yaml
global:
  name: consul
  datacenter: dc1

ui:
  enabled: true
  service:
    enabled: true
  # Metrics configuration for Consul UI
  metrics:
    enabled: true
    provider: "prometheus"
    baseURL: "http://prometheus-server.consul.svc.cluster.local:9090"

# Enable metrics collection from Envoy sidecars
connectInject:
  enabled: true
  default: true
  transparentProxy:
    defaultEnabled: true
  metrics:
    defaultEnabled: true
    defaultEnableMerging: true
    enableGatewayMetrics: true
```

Apply the configuration:

```bash
helm upgrade consul hashicorp/consul \
  --namespace consul \
  --values consul-values.yaml
```

### Option B: Using ConfigMap (Manual)

If you can't upgrade Consul, you can add a ConfigMap with UI configuration:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: consul-ui-config
  namespace: consul
data:
  ui-config.json: |
    {
      "ui_config": {
        "enabled": true,
        "metrics_provider": "prometheus",
        "metrics_proxy": {
          "base_url": "http://prometheus-server.consul.svc.cluster.local:9090"
        }
      }
    }
```

Then mount this ConfigMap in the Consul server pods and restart them.

## Step 3: Configure Prometheus to Scrape Envoy Metrics

### Option A: Using Prometheus Operator (ServiceMonitor)

Create a ServiceMonitor to scrape Envoy sidecar metrics:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: consul-connect-injected-services
  namespace: consul
  labels:
    app: consul
spec:
  selector:
    matchLabels:
      # This will match all services with Consul sidecars
      consul.hashicorp.com/connect-inject-status: "injected"
  namespaceSelector:
    any: true
  endpoints:
    - port: envoy-metrics
      interval: 30s
      path: /metrics
```

### Option B: Using Prometheus Configuration (Static Config)

Add to your Prometheus configuration (`prometheus.yml`):

```yaml
scrape_configs:
  - job_name: 'consul-connect-envoy'
    kubernetes_sd_configs:
      - role: pod
    relabel_configs:
      # Only scrape pods with Consul Connect injection
      - source_labels: [__meta_kubernetes_pod_annotation_consul_hashicorp_com_connect_inject_status]
        action: keep
        regex: injected
      # Use the prometheus.io/port annotation
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_port]
        action: replace
        target_label: __address__
        regex: ([^:]+)(?::\d+)?
        replacement: $1:20200
      # Add service name label
      - source_labels: [__meta_kubernetes_pod_label_app_kubernetes_io_name]
        action: replace
        target_label: service
      # Add namespace label
      - source_labels: [__meta_kubernetes_namespace]
        action: replace
        target_label: namespace
```

## Step 4: Verify Prometheus is Scraping

### Check Prometheus Targets

1. Port-forward to Prometheus:
   ```bash
   kubectl port-forward -n consul svc/prometheus-server 9090:9090
   ```

2. Open http://localhost:9090/targets

3. Look for targets with job name `consul-connect-envoy` or similar

4. Verify targets are "UP" and showing recent scrapes

### Query Metrics in Prometheus

Test that metrics are available:

```promql
# Request rate
rate(envoy_cluster_upstream_rq_total[5m])

# Error rate  
rate(envoy_cluster_upstream_rq_xx{envoy_response_code_class="5"}[5m])

# Latency (p99)
histogram_quantile(0.99, rate(envoy_cluster_upstream_rq_time_bucket[5m]))
```

## Step 5: Verify Consul UI Shows Metrics

1. Access Consul UI:
   ```bash
   kubectl port-forward -n consul svc/consul-ui 8500:443
   ```

2. Open https://localhost:8500

3. Navigate to **Services** → select a service (e.g., `frontend`)

4. Check the **Metrics** section - you should now see:
   - Request Rate graph
   - Error Rate graph
   - P50/P99 Latency graphs

5. Check the **Topology** view - connections should show metrics

## Troubleshooting

### Metrics Still Empty After Configuration

**Problem**: Consul UI configured but metrics still don't appear

**Solutions**:

1. **Check Prometheus URL is correct**:
   ```bash
   # From Consul server pod, test Prometheus connectivity
   kubectl exec -it consul-server-0 -n consul -- \
     wget -qO- http://prometheus-server.consul.svc.cluster.local:9090/api/v1/query?query=up
   ```

2. **Verify Envoy metrics are being scraped**:
   ```bash
   # Query Prometheus for Envoy metrics
   curl 'http://localhost:9090/api/v1/query?query=envoy_cluster_upstream_rq_total'
   ```

3. **Check Consul server logs**:
   ```bash
   kubectl logs -n consul consul-server-0 | grep -i metrics
   ```

4. **Verify NetworkPolicies aren't blocking**:
   - Consul servers need to reach Prometheus
   - Prometheus needs to scrape pods in tracing-demo namespace

### Prometheus Not Scraping Envoy Sidecars

**Problem**: Prometheus targets show no Envoy endpoints

**Solutions**:

1. **Verify prometheus.io annotations on pods**:
   ```bash
   kubectl get pod -n tracing-demo -l app.kubernetes.io/name=frontend \
     -o jsonpath='{.items[0].metadata.annotations}' | grep prometheus
   ```
   
   Should show:
   ```
   prometheus.io/path: /metrics
   prometheus.io/port: 20200
   prometheus.io/scrape: true
   ```

2. **Test Envoy metrics endpoint directly**:
   ```bash
   kubectl exec -it <pod-name> -n tracing-demo -c consul-dataplane -- \
     wget -qO- http://localhost:20200/metrics | head -50
   ```

3. **Check Prometheus scrape configuration**:
   ```bash
   kubectl exec -it <prometheus-pod> -n consul -- \
     cat /etc/prometheus/prometheus.yml | grep -A20 consul
   ```

### Metrics Show But Are Incorrect

**Problem**: Metrics appear but show wrong values or no data

**Solutions**:

1. **Generate traffic to populate metrics**:
   ```bash
   cd loadtest
   ./simple-load.sh
   ```

2. **Wait for scrape interval** (usually 30s-1m)

3. **Check metric labels match Consul's expectations**:
   - Consul UI expects specific Envoy metric names
   - Verify `envoy_cluster_upstream_rq_*` metrics exist

4. **Verify time range in Consul UI**:
   - Default is last 5 minutes
   - Adjust if needed to see historical data

## Example: Complete Consul Helm Values with Metrics

```yaml
global:
  name: consul
  datacenter: dc1
  image: "hashicorp/consul:1.17.0"
  imageK8S: "hashicorp/consul-k8s-control-plane:1.3.0"

server:
  replicas: 3
  bootstrapExpect: 3
  storage: 10Gi

ui:
  enabled: true
  service:
    enabled: true
    type: ClusterIP
  metrics:
    enabled: true
    provider: "prometheus"
    baseURL: "http://prometheus-server.consul.svc.cluster.local:9090"

connectInject:
  enabled: true
  default: true
  transparentProxy:
    defaultEnabled: true
  metrics:
    defaultEnabled: true
    defaultEnableMerging: true
    enableGatewayMetrics: true
  # Ensure prometheus annotations are added
  annotations: |
    "prometheus.io/scrape": "true"
    "prometheus.io/port": "20200"
    "prometheus.io/path": "/metrics"

prometheus:
  enabled: true
```

## Metrics Available in Consul UI

Once configured, you'll see:

### Service Overview Page
- **Request Rate**: Requests per second
- **Error Rate**: Percentage of 5xx responses
- **P50 Latency**: Median response time
- **P99 Latency**: 99th percentile response time

### Topology View
- **Per-connection metrics**: Request rate and success rate for each upstream
- **Color coding**: Green (healthy), Yellow (warnings), Red (errors)
- **Hover details**: Detailed metrics on hover

### Upstream/Downstream Lists
- **Request counts**: Total requests to/from each service
- **Success rates**: Percentage of successful requests
- **Latency**: Response time metrics

## Related Documentation

- [Consul UI Metrics](https://developer.hashicorp.com/consul/docs/connect/observability/ui-visualization)
- [Consul Metrics Configuration](https://developer.hashicorp.com/consul/docs/agent/config/config-files#ui_config)
- [Prometheus Kubernetes SD](https://prometheus.io/docs/prometheus/latest/configuration/configuration/#kubernetes_sd_config)
- [Envoy Metrics](https://www.envoyproxy.io/docs/envoy/latest/configuration/observability/statistics)

## Quick Reference Commands

```bash
# Diagnose metrics configuration
./diagnose-consul-metrics.sh

# Check Prometheus targets
kubectl port-forward -n consul svc/prometheus-server 9090:9090
# Open: http://localhost:9090/targets

# Test Envoy metrics endpoint
kubectl exec -it <pod> -n tracing-demo -c consul-dataplane -- \
  wget -qO- http://localhost:20200/metrics

# Check Consul UI config
kubectl exec -it consul-server-0 -n consul -- \
  cat /consul/config/server.json | grep -A10 ui_config

# Generate traffic for metrics
cd loadtest && ./simple-load.sh