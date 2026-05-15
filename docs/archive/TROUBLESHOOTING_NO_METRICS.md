# Troubleshooting: "No Data" in Consul UI and Grafana

## What You're Seeing

Based on your screenshot:

### Consul UI (Left Side)
- ✅ **Topology graph works** - shows cart, catalog, frontend, zipkin connections
- ✅ **Services are healthy** - all show 100% green
- ❌ **No traffic metrics** - shows "0 RPS, 0 ER, 0 RX, 0 TX"

### Grafana Dashboard (Right Side)
- ❌ **All panels show "No data"**
- Dashboard queries are configured but returning empty results

## Root Cause Analysis

The "0 RPS" (0 Requests Per Second) in Consul UI tells us there are **TWO possible issues**:

### Issue 1: No Traffic (Most Likely)
If there's no traffic flowing through the services, there are no metrics to collect.

### Issue 2: Metrics Not Being Collected
Even if traffic exists, Prometheus might not be scraping the metrics.

## Diagnostic Steps

### Step 1: Check if Traffic is Flowing

```bash
# Check if frontend service is accessible
kubectl get svc -n tracing-demo frontend

# Try to access the frontend
kubectl port-forward -n tracing-demo svc/frontend 8080:8080
# Then visit: http://localhost:8080
```

**Expected Result:** You should be able to access the frontend application.

**If it fails:** The application itself has issues (not a metrics problem).

### Step 2: Generate Test Traffic

```bash
cd /Users/chrislovett/hashi/monitoring/tracing/zipkin-otel-microdemo/loadtest
./simple-load.sh
```

**What this does:**
- Sends requests to the frontend service
- Frontend calls catalog, cart, checkout
- Creates traffic that generates metrics

**Expected Result:** After 30-60 seconds, you should see:
- RPS > 0 in Consul UI
- Data appearing in Grafana dashboards

### Step 3: Verify Metrics Are Being Exposed

```bash
# Pick a pod to test
POD=$(kubectl get pods -n tracing-demo -l app.kubernetes.io/name=frontend -o jsonpath='{.items[0].metadata.name}')

# Check if metrics endpoint works
kubectl exec -n tracing-demo $POD -c consul-dataplane -- wget -q -O- http://localhost:20200/metrics | head -20
```

**Expected Result:** Should see Envoy metrics like:
```
envoy_cluster_upstream_rq_total{...} 123
envoy_cluster_upstream_rq_time_bucket{...} 456
```

**If empty:** Metrics merging is still not working - run `./fix-metrics-merging.sh` again.

### Step 4: Verify Prometheus is Scraping

```bash
# Port forward to Prometheus
kubectl port-forward -n observability svc/prometheus-server 9090:80

# In another terminal or browser, check targets
# Visit: http://localhost:9090/targets
# Look for: kubernetes-pods job with tracing-demo namespace pods
```

**Expected Result:** Targets should show:
- State: UP (green)
- Labels: namespace="tracing-demo", pod="frontend-xxx"
- Last Scrape: Recent timestamp

**If DOWN or missing:** Prometheus can't reach the pods (NetworkPolicy issue).

### Step 5: Query Prometheus Directly

```bash
# With port-forward still active, query for metrics
curl 'http://localhost:9090/api/v1/query?query=envoy_cluster_upstream_rq_total{namespace="tracing-demo"}' | jq '.data.result | length'
```

**Expected Result:** Should return a number > 0 (number of metric series).

**If 0:** Prometheus has no metrics for tracing-demo namespace.

## Common Issues and Fixes

### Issue: "0 RPS" in Consul UI

**Cause:** No traffic flowing through services.

**Fix:**
```bash
cd loadtest
./simple-load.sh
```

Wait 1-2 minutes, then refresh Consul UI.

### Issue: Grafana Shows "No data"

**Possible Causes:**

1. **Wrong time range** - Check if "Last 15 minutes" has data
   - Try changing to "Last 1 hour" or "Last 6 hours"

2. **Wrong namespace filter** - Check dashboard variables
   - Ensure `namespace` is set to "tracing-demo"
   - Ensure `service` is set to "catalog" or "All"

3. **Prometheus data source not configured**
   - Go to Grafana → Configuration → Data Sources
   - Verify Prometheus URL: `http://prometheus-server.observability.svc.cluster.local`

4. **Query syntax issues**
   - Check if queries use correct metric names
   - Should be: `envoy_cluster_upstream_rq_total{namespace="tracing-demo"}`

### Issue: Metrics Endpoint Returns Nothing

**Cause:** Metrics merging not configured properly.

**Fix:**
```bash
cd /Users/chrislovett/hashi/monitoring/tracing/zipkin-otel-microdemo
./fix-metrics-merging.sh
```

This adds the missing Helm values:
- `defaultMergedMetricsPort: 20200`
- `defaultPrometheusScrapePort: 20200`
- `defaultPrometheusScrapePath: /metrics`

### Issue: Prometheus Targets Show "DOWN"

**Possible Causes:**

1. **NetworkPolicy blocking traffic**
   ```bash
   kubectl get networkpolicy -n tracing-demo
   kubectl get networkpolicy -n observability
   ```

2. **Pods not ready**
   ```bash
   kubectl get pods -n tracing-demo
   ```

3. **Wrong port in annotations**
   ```bash
   kubectl get pod -n tracing-demo <pod-name> -o yaml | grep prometheus.io
   ```
   Should show: `prometheus.io/port: "20200"`

## Quick Diagnostic Script

Run this to check everything at once:

```bash
cd /Users/chrislovett/hashi/monitoring/tracing/zipkin-otel-microdemo
./diagnose-envoy-metrics.sh
```

This will check:
- Pod annotations
- Metrics endpoints
- Prometheus connectivity
- consul-dataplane configuration

## Expected Behavior After Fix

Once everything is working:

### Consul UI Should Show:
- **RPS** (Requests Per Second): > 0 (e.g., 5-50 RPS depending on load)
- **ER** (Error Rate): 0% or small percentage
- **RX/TX**: Network traffic in/out

### Grafana Should Show:
- **Request Rate graphs**: Lines showing requests over time
- **Success Rate**: Percentage near 100%
- **Latency graphs**: P50, P95, P99 percentiles
- **TCP metrics**: Inbound/outbound bytes

## Still Not Working?

If after following all steps you still see "No data":

1. **Check Consul UI metrics configuration:**
   ```bash
   kubectl exec -n consul consul-server-0 -- cat /consul/config/server.json | jq '.ui_config'
   ```
   Should show metrics_provider and metrics_proxy settings.

2. **Check Consul server logs:**
   ```bash
   kubectl logs -n consul consul-server-0 | grep -i metric
   ```

3. **Verify Consul can reach Prometheus:**
   ```bash
   kubectl exec -n consul consul-server-0 -- wget -q -O- --timeout=5 http://prometheus-server.observability.svc.cluster.local/api/v1/query?query=up
   ```

4. **Check browser console** (F12 in browser):
   - Look for errors when loading Consul UI metrics
   - Check Network tab for failed API calls

## Summary Checklist

- [ ] Services are deployed and healthy
- [ ] Traffic is flowing (run load test)
- [ ] Metrics endpoint returns data (port 20200)
- [ ] Prometheus targets show UP
- [ ] Prometheus has metrics data
- [ ] Consul UI config has metrics_proxy
- [ ] Grafana data source is configured
- [ ] Dashboard time range includes recent data

If all checkboxes are ✅ but still no data, there may be a deeper configuration issue. Share additional screenshots or logs for further diagnosis.