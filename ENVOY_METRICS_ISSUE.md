# Envoy Metrics Issue - Root Cause Analysis

## Problem Statement

Envoy/consul-dataplane metrics are not being exposed on port 20200, causing:
1. Empty metrics in Consul UI
2. Empty Grafana dashboards
3. Prometheus showing targets as "up" but collecting 0 metrics

## Root Cause

Based on diagnostic output:

### ✅ What's Working
- Prometheus annotations are correct (`prometheus.io/scrape: "true"`, `prometheus.io/port: "20200"`)
- Prometheus targets show pods as "up" and healthy
- Consul Helm values have `connectInject.metrics.defaultEnabled: true`
- Traffic is flowing through the application (load test shows 200 responses)

### ❌ What's NOT Working
- **Port 20200 returns NO metrics** (the configured Prometheus scrape port)
- **Port 19000 (standard Envoy admin) is accessible** but has metrics
- **Envoy admin interface is not exposed externally**
- consul-dataplane logs show connection issues to Consul servers

## Technical Analysis

### The Issue
The Prometheus scrape configuration expects metrics on port **20200**, but:
1. Envoy admin interface (with metrics) is on port **19000**
2. Port 20200 is configured in annotations but not actually serving metrics
3. There's a mismatch between the configured port and the actual metrics endpoint

### Why This Happens
In Consul Service Mesh with consul-dataplane:
- Envoy admin interface runs on port 19000 by default
- Metrics are available at `http://localhost:19000/stats/prometheus`
- The `prometheus.io/port: "20200"` annotation expects a **metrics merging endpoint**
- Metrics merging combines application metrics + Envoy metrics on a single port
- **If metrics merging isn't working, port 20200 has nothing to serve**

## Solution Options

### Option 1: Fix Metrics Merging (Recommended)
Enable proper metrics merging so port 20200 serves combined metrics:

```yaml
connectInject:
  metrics:
    defaultEnabled: true
    defaultEnableMerging: true  # Already set
    defaultMergedMetricsPort: 20200
    defaultPrometheusScrapePort: 20200
    defaultPrometheusScrapePath: "/metrics"
```

### Option 2: Change Prometheus to Scrape Port 19000
Update pod annotations to point to the actual Envoy admin port:

```yaml
annotations:
  prometheus.io/scrape: "true"
  prometheus.io/port: "19000"  # Change from 20200
  prometheus.io/path: "/stats/prometheus"
```

### Option 3: Enable Envoy Admin Bind
Configure consul-dataplane to expose admin interface on 0.0.0.0:

```yaml
connectInject:
  consulDataplane:
    extraArgs:
      - "-envoy-admin-bind-address=0.0.0.0"
      - "-envoy-admin-bind-port=19000"
```

## Recommended Fix

**Use Option 2** (simplest and most reliable):
1. Update Helm chart to change prometheus.io/port annotation from 20200 to 19000
2. Add prometheus.io/path annotation to "/stats/prometheus"
3. Upgrade Helm release
4. Restart pods to apply new annotations

This works because:
- Envoy admin interface IS serving metrics on port 19000
- We just need to tell Prometheus to scrape the correct port
- No complex metrics merging configuration needed
- Immediate fix without debugging merging issues

## Next Steps

1. Run the fix script: `./fix-envoy-metrics-port.sh`
2. Verify metrics appear in Prometheus
3. Check Consul UI for metrics
4. Verify Grafana dashboards populate

## References

- Consul Dataplane Metrics: https://developer.hashicorp.com/consul/docs/connect/dataplane
- Envoy Admin Interface: https://www.envoyproxy.io/docs/envoy/latest/operations/admin
- Prometheus Kubernetes SD: https://prometheus.io/docs/prometheus/latest/configuration/configuration/#kubernetes_sd_config