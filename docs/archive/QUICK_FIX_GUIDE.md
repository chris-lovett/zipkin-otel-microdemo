# Quick Fix Guide: "No Data" in Consul UI and Grafana

## TL;DR - Most Common Issue

**You see "0 RPS" in Consul UI and "No data" in Grafana?**

**99% of the time, this means: NO TRAFFIC IS FLOWING**

### Quick Fix (30 seconds)

```bash
cd /Users/chrislovett/hashi/monitoring/tracing/zipkin-otel-microdemo/loadtest
./simple-load.sh
```

Wait 1-2 minutes, then refresh Consul UI and Grafana. You should now see data.

---

## Automated Troubleshooting

Run this interactive script to diagnose and fix issues:

```bash
cd /Users/chrislovett/hashi/monitoring/tracing/zipkin-otel-microdemo
./troubleshoot-no-metrics.sh
```

This script will:
1. ✅ Check if services are deployed
2. ✅ Check if traffic is flowing
3. ✅ Check metrics endpoints
4. ✅ Check Prometheus configuration
5. ✅ Check Consul UI configuration
6. ✅ Offer to fix issues automatically

---

## Manual Troubleshooting Steps

### Step 1: Verify Services Are Running

```bash
kubectl get pods -n tracing-demo
```

**Expected:** All pods should be `Running` with `2/2` containers ready.

**If not:** Wait for pods to be ready or check deployment issues.

---

### Step 2: Generate Traffic

```bash
# Option 1: Simple load test (recommended)
cd loadtest
./simple-load.sh

# Option 2: Manual test
kubectl port-forward -n tracing-demo svc/frontend 8080:8080
# Visit http://localhost:8080 in browser
```

**Why this matters:** Metrics only exist when requests flow through services.

---

### Step 3: Verify Metrics Are Being Exposed

```bash
# Pick a pod
POD=$(kubectl get pods -n tracing-demo -l app.kubernetes.io/name=frontend -o jsonpath='{.items[0].metadata.name}')

# Check metrics endpoint
kubectl exec -n tracing-demo $POD -c consul-dataplane -- wget -q -O- http://localhost:20200/metrics | head -20
```

**Expected:** Should see Envoy metrics like `envoy_cluster_upstream_rq_total`.

**If empty:** Run `./fix-metrics-merging.sh`

---

### Step 4: Check Prometheus Is Scraping

```bash
# Port forward to Prometheus
kubectl port-forward -n observability svc/prometheus-server 9090:80

# Visit http://localhost:9090/targets
# Look for: kubernetes-pods job with tracing-demo namespace
```

**Expected:** Targets should show `UP` (green) status.

**If DOWN:** Check NetworkPolicies or pod annotations.

---

### Step 5: Query Prometheus Directly

```bash
# With port-forward active
curl 'http://localhost:9090/api/v1/query?query=envoy_cluster_upstream_rq_total{namespace="tracing-demo"}' | jq
```

**Expected:** Should return metric data.

**If empty:** Prometheus isn't receiving metrics from pods.

---

## Common Issues and One-Line Fixes

### Issue: "0 RPS" in Consul UI

**Cause:** No traffic flowing.

**Fix:**
```bash
cd loadtest && ./simple-load.sh
```

---

### Issue: Grafana Shows "No data"

**Possible causes:**

1. **Wrong time range**
   - Change to "Last 1 hour" or "Last 6 hours"

2. **Wrong namespace filter**
   - Set `namespace` variable to "tracing-demo"

3. **No traffic**
   - Run load test (see above)

---

### Issue: Metrics Endpoint Returns Nothing

**Cause:** Metrics merging not configured.

**Fix:**
```bash
./fix-metrics-merging.sh
```

Wait 2-3 minutes for pods to restart, then test again.

---

### Issue: Consul UI Doesn't Show Metrics Tab

**Cause:** UI metrics configuration missing.

**Fix:**
```bash
./fix-consul-ui-metrics-v2.sh
```

---

## Verification Checklist

After applying fixes, verify everything works:

```bash
# 1. Check services are healthy
kubectl get pods -n tracing-demo

# 2. Generate traffic
cd loadtest && ./simple-load.sh &

# 3. Wait 30 seconds
sleep 30

# 4. Check metrics endpoint
POD=$(kubectl get pods -n tracing-demo -l app.kubernetes.io/name=frontend -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n tracing-demo $POD -c consul-dataplane -- wget -q -O- http://localhost:20200/metrics | grep envoy_cluster_upstream_rq_total

# 5. Check Prometheus has data
kubectl port-forward -n observability svc/prometheus-server 9090:80 &
sleep 5
curl -s 'http://localhost:9090/api/v1/query?query=envoy_cluster_upstream_rq_total{namespace="tracing-demo"}' | jq '.data.result | length'

# Should return a number > 0
```

---

## Expected Results After Fix

### Consul UI Should Show:
- **RPS**: 5-50 (depending on load)
- **Error Rate**: 0% or small percentage
- **RX/TX**: Network traffic metrics
- **Graphs**: Lines showing traffic over time

### Grafana Should Show:
- **Request Rate**: Lines showing requests/sec
- **Success Rate**: ~100%
- **Latency**: P50, P95, P99 percentiles
- **TCP Metrics**: Bytes in/out

---

## Still Not Working?

If you've tried everything above and still see "No data":

1. **Run the automated troubleshooter:**
   ```bash
   ./troubleshoot-no-metrics.sh
   ```

2. **Check detailed documentation:**
   - See `TROUBLESHOOTING_NO_METRICS.md` for comprehensive guide

3. **Verify Consul configuration:**
   ```bash
   kubectl exec -n consul consul-server-0 -- cat /consul/config/server.json | jq '.ui_config'
   ```

4. **Check browser console** (F12):
   - Look for errors when loading Consul UI
   - Check Network tab for failed API calls

5. **Review logs:**
   ```bash
   # Consul server logs
   kubectl logs -n consul consul-server-0 | grep -i metric
   
   # Application pod logs
   kubectl logs -n tracing-demo $POD -c consul-dataplane | grep -i metric
   ```

---

## Summary

**Most common issue:** No traffic → No metrics → "No data"

**Quick fix:** Run `./simple-load.sh` to generate traffic

**If that doesn't work:** Run `./troubleshoot-no-metrics.sh` for automated diagnosis

**For deep dive:** See `TROUBLESHOOTING_NO_METRICS.md`