# Root Cause Analysis: Why Metrics Show "No Data"

## Problem Statement

Consul UI shows "0 RPS" and Grafana dashboards show "No data" despite:
- All services deployed and healthy
- Consul UI topology graph working
- Load test script running successfully
- Prometheus and Grafana configured correctly

## Root Cause Discovered

**The load test was bypassing the Consul service mesh entirely.**

### How Traffic Was Flowing (WRONG)

```
Load Test (simple-load.sh)
    ↓
OpenShift Route (external ingress)
    ↓
Frontend Service
    ↓
Frontend Container (direct)
    ↓
Backend Services (direct)
```

**Result:** Traffic never went through Envoy proxies, so no Envoy metrics were generated.

### How Traffic SHOULD Flow (CORRECT)

```
Load Test (mesh-load.sh)
    ↓
kubectl exec into Frontend Pod
    ↓
Frontend Container → localhost:8080
    ↓
Envoy Sidecar (intercepts outbound)
    ↓
Backend Services via Consul Service Mesh
    ↓
Envoy Sidecars (generate metrics)
```

**Result:** All traffic flows through Envoy, generating metrics for Prometheus.

## Technical Details

### Why simple-load.sh Bypassed the Mesh

The original load test used:
```bash
FRONTEND_URL="https://frontend-tracing-demo.apps.rosa.cluster1.6cxo.p3.openshiftapps.com"
curl "$FRONTEND_URL/products"
```

This hits the **OpenShift Route**, which is an external ingress that routes directly to the application container, bypassing the Envoy sidecar.

### Why This Matters for Metrics

Consul Service Mesh metrics come from **Envoy proxies**, not the application containers. Specifically:

1. **Inbound metrics**: Generated when traffic enters through Envoy's inbound listener
2. **Outbound metrics**: Generated when traffic exits through Envoy's outbound listener
3. **Upstream metrics**: Generated when Envoy makes requests to upstream services

When traffic bypasses Envoy:
- No `envoy_cluster_upstream_rq_total` metrics
- No `envoy_http_downstream_rq_total` metrics
- No latency metrics (P50, P95, P99)
- No error rate metrics
- Consul UI shows "0 RPS" because it queries these Envoy metrics

### Why mesh-load.sh Works

The new script uses:
```bash
kubectl exec -n tracing-demo deployment/frontend -c frontend -- \
    wget -q -O- http://localhost:8080/products
```

This:
1. Executes commands **inside** the frontend container
2. Makes requests to `localhost:8080` (the application port)
3. Envoy intercepts these requests via iptables rules
4. Traffic flows through the mesh to backend services
5. All Envoy proxies generate metrics

## Evidence

### Before Fix (No Metrics)

```bash
# Check Envoy stats
kubectl exec -n tracing-demo $POD -c consul-dataplane -- \
    wget -q -O- http://localhost:19000/stats | grep downstream_rq_total

# Result: No output (0 requests)
```

### After Fix (Metrics Generated)

```bash
# Same command after running mesh-load.sh
# Result: Shows request counts like:
# http.ingress_http.downstream_rq_total: 150
# cluster.local_app.upstream_rq_total: 150
```

## Why This Was Hard to Diagnose

1. **Load test appeared to work**: Got 200/404 responses, so seemed functional
2. **Services were healthy**: All pods running, topology graph working
3. **Configuration was correct**: Prometheus, Consul UI, metrics merging all configured properly
4. **No obvious errors**: No failed pods, no error logs

The issue was **architectural** - traffic wasn't flowing through the mesh at all.

## Lessons Learned

### For Load Testing Service Mesh Applications

1. **Always test from inside the mesh**: Use `kubectl exec` to generate traffic from within pods
2. **Verify Envoy metrics first**: Check `localhost:19000/stats` before checking Prometheus
3. **Understand ingress vs mesh traffic**: External ingress may bypass sidecars
4. **Test the data plane, not just the control plane**: Topology graph working ≠ metrics working

### For Troubleshooting "No Metrics"

1. **Check if traffic is flowing through Envoy**: Look at Envoy admin stats
2. **Verify traffic path**: Trace how requests flow from source to destination
3. **Don't assume load tests are correct**: Verify they're actually using the mesh
4. **Test incrementally**: Start with simple curl from inside a pod

## Solution Summary

### Quick Fix

Use the new mesh-aware load test:
```bash
cd /Users/chrislovett/hashi/monitoring/tracing/zipkin-otel-microdemo/loadtest
./mesh-load.sh
```

### Why It Works

- Generates traffic **inside** the service mesh
- All requests flow through Envoy sidecars
- Envoy generates metrics for Prometheus
- Consul UI and Grafana can display the data

### Expected Results

After running `mesh-load.sh` for 30-60 seconds:
- Consul UI shows RPS > 0 (e.g., 5-20 RPS)
- Grafana dashboards populate with data
- Prometheus has `envoy_*` metrics for tracing-demo namespace
- Topology graph shows traffic flow with metrics

## Related Files

- [`mesh-load.sh`](loadtest/mesh-load.sh) - Correct load test that uses the mesh
- [`simple-load.sh`](loadtest/simple-load.sh) - Original load test (bypasses mesh)
- [`TROUBLESHOOTING_NO_METRICS.md`](TROUBLESHOOTING_NO_METRICS.md) - Comprehensive troubleshooting guide
- [`QUICK_FIX_GUIDE.md`](QUICK_FIX_GUIDE.md) - Quick reference for common issues

## Conclusion

The "No data" issue was caused by the load test bypassing the service mesh entirely. The infrastructure was configured correctly, but traffic wasn't flowing through Envoy proxies, so no metrics were generated.

**Key Takeaway:** When troubleshooting service mesh metrics, always verify that traffic is actually flowing through the mesh, not just that the mesh is configured correctly.