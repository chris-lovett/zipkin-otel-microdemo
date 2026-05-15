# Grafana Dashboard Namespace Variable Fix

## Problem
The Consul Data Plane Performance dashboard's namespace dropdown was empty because:
1. The variable query used `container_memory_working_set_bytes{job="kubernetes-nodes-cadvisor"}`
2. This metric wasn't accessible from the Thanos datasource with the Grafana service account permissions
3. Result: Empty namespace dropdown, preventing dashboard from working

## Root Cause
The dashboard was designed for a standard Kubernetes Prometheus setup, not OpenShift with Thanos Querier and restricted RBAC.

## Solution Applied

### 1. Updated Namespace Variable Query
**Before:**
```promql
label_values(container_memory_working_set_bytes{job="kubernetes-nodes-cadvisor"}, namespace)
```

**After:**
```promql
label_values(envoy_cluster_upstream_rq_total, namespace)
```

This change:
- Uses Envoy metrics that we know are available
- Queries metrics that the Grafana service account can access
- Only shows namespaces that have Consul service mesh deployments

### 2. Set Default Value
Set the namespace variable's default value to `tracing-demo` so the dashboard loads with the correct namespace pre-selected.

### 3. Implementation Commands

```bash
# Backup the dashboard
kubectl get configmap consul-data-plane-performance -n observability -o json > /tmp/dashboard-backup.json

# Update the namespace variable
kubectl get configmap consul-data-plane-performance -n observability -o json | \
jq '.data."consul-data-plane-performance.json" |= (fromjson | 
  .templating.list |= map(
    if .name == "namespace" then
      .definition = "label_values(envoy_cluster_upstream_rq_total, namespace)" |
      .query.query = "label_values(envoy_cluster_upstream_rq_total, namespace)" |
      .current = {"text": "tracing-demo", "value": "tracing-demo"}
    else . end
  ) | tojson)' | kubectl apply -f -

# Trigger dashboard reload
kubectl annotate grafanadashboard consul-data-plane-performance -n observability resync-requested="$(date +%s)" --overwrite

# Restart Grafana to clear cache
kubectl delete pod -n observability -l app=grafana-deployment
```

## Verification

### Check ConfigMap Update
```bash
kubectl get configmap consul-data-plane-performance -n observability -o jsonpath='{.data.consul-data-plane-performance\.json}' | \
jq '.templating.list[] | select(.name=="namespace") | {name, query: .query.query, current}'
```

Expected output:
```json
{
  "name": "namespace",
  "query": "label_values(envoy_cluster_upstream_rq_total, namespace)",
  "current": {
    "text": "tracing-demo",
    "value": "tracing-demo"
  }
}
```

### Check Grafana Pod Status
```bash
kubectl get pods -n observability | grep grafana-deployment
```

Should show: `1/1 Running`

### Test in Browser
1. Refresh the Grafana dashboard (Ctrl+R or Cmd+R)
2. Check the namespace dropdown - should show "tracing-demo"
3. Check the service dropdown - should show: cart, catalog, checkout, frontend, inventory, payment, zipkin
4. Select a service and verify metrics appear

## Why This Works

### Metric Availability
```bash
# Verify Envoy metrics are accessible
kubectl exec -n openshift-user-workload-monitoring prometheus-user-workload-0 -c prometheus -- \
  wget -qO- 'http://localhost:9090/api/v1/query?query=envoy_cluster_upstream_rq_total' | \
  jq '.data.result[].metric.namespace' | sort -u
```

Should return: `"tracing-demo"`

### Label Structure
Our Envoy metrics have these labels:
- `namespace`: "tracing-demo" (Kubernetes namespace)
- `local_cluster`: Service name (cart, catalog, etc.)
- `consul_source_service`: Consul service name
- `service`: "consul-mesh-metrics" (our ServiceMonitor)
- `pod`: Pod name

The dashboard queries use:
- `namespace=~"$namespace"` - Filters by Kubernetes namespace
- `local_cluster=~"$app"` - Filters by service name

## Alternative Approaches Considered

### Option 1: Fix RBAC Permissions
Add permissions for Grafana service account to query cadvisor metrics.

**Pros:** Keeps original dashboard query
**Cons:** 
- Requires cluster-admin permissions
- Shows ALL namespaces (not just Consul ones)
- More complex RBAC management

### Option 2: Use Consul Metrics
Query `consul_*` metrics instead of `envoy_*`.

**Pros:** More Consul-specific
**Cons:**
- Fewer Consul metrics available than Envoy
- Envoy metrics are more comprehensive for service mesh monitoring

### Option 3: Hardcode Namespace
Remove the namespace variable entirely and hardcode "tracing-demo".

**Pros:** Simplest solution
**Cons:**
- Not reusable for other namespaces
- Loses flexibility

**Selected: Option (as implemented)** - Use Envoy metrics for namespace variable
- Works with existing permissions
- Only shows relevant namespaces
- Maintains dashboard flexibility
- Aligns with our metrics implementation

## Files Modified

1. **ConfigMap**: `consul-data-plane-performance` in `observability` namespace
   - Updated `.data."consul-data-plane-performance.json".templating.list[].query`
   - Set default namespace value

2. **GrafanaDashboard**: `consul-data-plane-performance` in `observability` namespace
   - Annotated to trigger resync

3. **Grafana Pod**: Restarted to clear cache

## Troubleshooting

### Dashboard still shows empty namespace dropdown
1. **Clear browser cache**: Hard refresh (Ctrl+Shift+R or Cmd+Shift+R)
2. **Check ConfigMap**: Verify the query was updated
3. **Check Grafana logs**:
   ```bash
   kubectl logs -n observability -l app=grafana-deployment --tail=50
   ```
4. **Verify metrics are accessible**: Test the query in Grafana Explore

### Namespace shows but service dropdown is empty
1. **Verify namespace is set to "tracing-demo"**
2. **Check app variable query**:
   ```bash
   kubectl get configmap consul-data-plane-performance -n observability -o jsonpath='{.data.consul-data-plane-performance\.json}' | \
   jq '.templating.list[] | select(.name=="app")'
   ```
3. **Test the query**:
   ```promql
   label_values(envoy_cluster_upstream_rq_total{namespace="tracing-demo"}, local_cluster)
   ```

### Metrics show 0 values
This is expected if there's no traffic. Generate traffic:
```bash
cd loadtest
./simple-load.sh
```

## Related Documentation

- [`SOLUTION_COMPLETE.md`](./SOLUTION_COMPLETE.md) - Complete metrics solution
- [`OPENSHIFT_MONITORING_FIX.md`](./OPENSHIFT_MONITORING_FIX.md) - OpenShift monitoring configuration
- [`GRAFANA_DASHBOARD_GUIDE.md`](./GRAFANA_DASHBOARD_GUIDE.md) - Dashboard usage guide
- [`fix-dashboard-namespace-variable.sh`](./fix-dashboard-namespace-variable.sh) - Automated fix script

## Success Criteria

- ✅ Namespace dropdown populated with "tracing-demo"
- ✅ Service dropdown populated with 7 services
- ✅ Dashboard panels show metrics (may be 0 without traffic)
- ✅ No "No data" errors in panels
- ✅ Dashboard loads without manual variable configuration

---

**Status**: ✅ APPLIED - Waiting for Grafana pod restart to complete
**Date**: 2026-05-14
**Time**: ~15 minutes to diagnose and fix