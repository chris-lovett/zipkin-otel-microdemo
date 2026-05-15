# Complete Metrics Fix Summary

## Current Problem

**Symptoms:**
- Consul UI shows "No Metrics Available" and "0 RPS" for all services
- Grafana dashboards show "No data" in all panels
- Prometheus targets for tracing-demo namespace show "DOWN" status

**Root Cause:**
consul-dataplane is configured to merge application metrics from `http://127.0.0.1:8080/metrics`, but the application containers don't expose a `/metrics` endpoint. This causes:

1. **404 errors every minute** in consul-dataplane logs:
   ```
   [ERROR] consul-dataplane.metrics: failed to scrape metrics: 
   url=http://127.0.0.1:8080/metrics error="status code 404"
   ```

2. **Invalid metrics format** on port 20200:
   - Instead of Prometheus metrics, it returns error text: "failed to"
   - Prometheus can't parse this: `strconv.ParseFloat: parsing "to": invalid syntax`

3. **All Prometheus scrape targets fail**:
   - Status: DOWN
   - No metrics collected
   - Consul UI and Grafana have no data to display

## The Solution

**Change Consul configuration to disable application metrics merging:**

```yaml
connectInject:
  metrics:
    defaultEnabled: true
    defaultEnableMerging: false  # ← KEY CHANGE: Disable app metrics merging
    enableGatewayMetrics: true
    defaultMergedMetricsPort: 20200
    defaultPrometheusScrapePort: 20200
    defaultPrometheusScrapePath: "/metrics"
```

This makes port 20200 expose **only Envoy metrics** (which always exist), avoiding the 404 error from trying to scrape non-existent application metrics.

## How to Apply the Fix

### Option 1: Automated Script (Recommended)

```bash
cd /Users/chrislovett/hashi/monitoring/tracing/zipkin-otel-microdemo
./fix-metrics-404-error.sh
```

This script will:
1. Update Consul Helm values
2. Upgrade Consul release
3. Restart application pods
4. Verify the fix

### Option 2: Manual Fix

1. **Get current Consul values:**
   ```bash
   helm get values -n consul consul > consul-values.yaml
   ```

2. **Edit the file** and add/update:
   ```yaml
   connectInject:
     metrics:
       defaultEnabled: true
       defaultEnableMerging: false
       enableGatewayMetrics: true
       defaultMergedMetricsPort: 20200
       defaultPrometheusScrapePort: 20200
       defaultPrometheusScrapePath: "/metrics"
   ```

3. **Apply the changes:**
   ```bash
   helm upgrade consul hashicorp/consul -n consul -f consul-values.yaml --wait
   ```

4. **Restart application pods:**
   ```bash
   kubectl rollout restart deployment -n tracing-demo --all
   kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=zipkin-otel-microdemo -n tracing-demo --timeout=300s
   ```

## Verification Steps

### 1. Check consul-dataplane logs (should have NO errors)

```bash
POD=$(kubectl get pods -n tracing-demo -l app.kubernetes.io/name=frontend -o jsonpath='{.items[0].metadata.name}')
kubectl logs -n tracing-demo $POD -c consul-dataplane --tail=20 | grep -i metric
```

**Expected:** No "failed to scrape metrics" errors

### 2. Check Prometheus targets (should be UP)

```bash
kubectl port-forward -n observability svc/prometheus-server 9090:80 &
sleep 3
curl -s 'http://localhost:9090/api/v1/targets' | jq '.data.activeTargets[] | select(.labels.namespace=="tracing-demo") | {pod: .labels.pod, health: .health}'
kill %1
```

**Expected:** All pods show `"health": "up"`

### 3. Verify metrics are available

```bash
curl -s 'http://localhost:9090/api/v1/query?query=envoy_cluster_upstream_rq_total{namespace="tracing-demo"}' | jq '.data.result | length'
```

**Expected:** Number > 0 (even if no traffic, Envoy metrics exist)

### 4. Generate traffic to see non-zero metrics

```bash
cd loadtest
./simple-load.sh
```

Wait 1-2 minutes, then check:
- **Consul UI:** Should show RPS > 0, metrics graphs populated
- **Grafana:** Should show data in all panels

## Timeline

After applying the fix:

- **0-2 minutes:** Pods restarting
- **2-3 minutes:** Prometheus scraping new metrics
- **3-5 minutes:** Consul UI and Grafana populate with data
- **After traffic generation:** Non-zero RPS and metrics visible

## What This Fixes

✅ consul-dataplane no longer tries to scrape non-existent app metrics  
✅ Port 20200 returns valid Prometheus metrics format  
✅ Prometheus can successfully scrape all pods  
✅ Consul UI receives metrics from Prometheus  
✅ Grafana dashboards display data  

## What This Doesn't Fix

❌ If there's no traffic, RPS will still be 0 (this is expected)  
❌ If Prometheus can't reach pods due to network issues  
❌ If Consul UI metrics proxy is misconfigured  

For those issues, see:
- [`TROUBLESHOOTING_NO_METRICS.md`](TROUBLESHOOTING_NO_METRICS.md)
- [`QUICK_FIX_GUIDE.md`](QUICK_FIX_GUIDE.md)

## Technical Details

### Why Metrics Merging Was Enabled

The Consul Helm chart defaults to `defaultEnableMerging: true` because many applications expose their own Prometheus metrics. The idea is to merge:
- Application metrics (e.g., business metrics, custom counters)
- Envoy sidecar metrics (e.g., request rates, latencies)

Into a single endpoint for Prometheus to scrape.

### Why It Failed Here

This demo application doesn't expose `/metrics` endpoints. When consul-dataplane tries to scrape `http://127.0.0.1:8080/metrics`, it gets 404, which breaks the entire metrics pipeline.

### The Fix

By setting `defaultEnableMerging: false`, we tell consul-dataplane:
- Don't try to scrape application metrics
- Only expose Envoy metrics on port 20200
- Envoy metrics always exist (even with 0 traffic)

This ensures Prometheus always gets valid metrics to scrape.

## Alternative Solutions

### Option A: Add /metrics endpoint to applications

If you want application-level metrics, you could:
1. Modify each service to expose `/metrics` endpoint
2. Keep `defaultEnableMerging: true`
3. Get both app and Envoy metrics merged

**Pros:** More comprehensive metrics  
**Cons:** Requires code changes to all services

### Option B: Use different ports for app metrics

Configure different ports:
- Port 8080: Application traffic
- Port 9090: Application metrics
- Port 20200: Merged metrics (Envoy + app)

Update Helm values:
```yaml
connectInject:
  metrics:
    defaultEnableMerging: true
    defaultMergedMetricsPort: 20200
    defaultPrometheusScrapePort: 20200
    defaultPrometheusScrapePath: "/metrics"
```

And add annotation to pods:
```yaml
annotations:
  consul.hashicorp.com/service-metrics-port: "9090"
  consul.hashicorp.com/service-metrics-path: "/metrics"
```

**Pros:** Clean separation of concerns  
**Cons:** More complex configuration

### Option C: Current fix (Recommended for this demo)

Disable merging, expose only Envoy metrics.

**Pros:** Simple, works immediately, no code changes  
**Cons:** No application-level metrics (but Envoy metrics are usually sufficient)

## Summary

The fix is simple: **disable application metrics merging** since the applications don't expose metrics endpoints. This allows Envoy metrics to flow properly to Prometheus, which then feeds Consul UI and Grafana.

Run `./fix-metrics-404-error.sh` to apply the fix automatically.