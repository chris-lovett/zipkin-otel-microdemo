# Grafana Dashboard Configuration Guide

## Issue
The Consul Service Mesh Performance dashboard shows data, but you need to configure the variables correctly to see your services.

## Dashboard Variables Configuration

### Current Dashboard URL
From Consul UI → Service Topology → Click "Open dashboard" on a service

### Variables at Top of Dashboard

#### 1. **datasource** 
- Should be: `Prometheus` (prometheus-thanos)
- This is correct ✅

#### 2. **namespace**
- **Current Issue**: Dropdown shows ALL Kubernetes namespaces
- **Required Value**: `tracing-demo`
- **How to Fix**: 
  1. Click the namespace dropdown at the top of the dashboard
  2. Scroll down and select `tracing-demo`
  3. The dashboard will refresh

#### 3. **service** (or **app**)
- **Current Issue**: May show "No data" or wrong services
- **Required Value**: One of: `cart`, `catalog`, `checkout`, `frontend`, `inventory`, `payment`, `zipkin`
- **How to Fix**:
  1. After selecting namespace=tracing-demo, this dropdown will populate
  2. Select the service you want to monitor (e.g., `cart`)

## Verification

After setting the variables correctly, you should see:
- ✅ Metrics appear in the panels
- ✅ Values may be 0 (no traffic yet)
- ✅ Graphs show time series data

## Generate Traffic to See Non-Zero Metrics

```bash
cd loadtest
./simple-load.sh
```

This will generate traffic and you'll see:
- Request rates increase
- Latency metrics populate
- Connection counts rise

## Dashboard Query Examples

The dashboard uses queries like:
```promql
# Active connections
sum by (app) (envoy_cluster_upstream_cx_active{
  app="$app",
  namespace=~"$namespace",
  envoy_cluster_name!~"consul-dataplane|prometheus.*|local_app|original-.*"
})

# Request rate
sum(rate(envoy_http_downstream_rq_total{
  namespace=~"$namespace",
  envoy_http_conn_manager_prefix="public_listener"
}[5m])) by (namespace)

# Latency percentiles
histogram_quantile(0.50, sum by (le) (
  rate(envoy_cluster_upstream_rq_time_bucket{
    namespace=~"$namespace",
    local_cluster=~"$app"
  }[5m])
))
```

## Available Metrics

Our implementation provides these Envoy metrics:
- `envoy_cluster_upstream_rq_total` - Total requests
- `envoy_cluster_upstream_rq_time_bucket` - Request latency histogram
- `envoy_cluster_upstream_cx_active` - Active connections
- `envoy_http_downstream_rq_total` - HTTP requests
- Plus 5,100+ other Envoy metrics

## Metric Labels

Each metric includes these labels:
- `namespace`: "tracing-demo"
- `local_cluster`: Service name (cart, catalog, etc.)
- `consul_source_service`: Consul service name
- `pod`: Pod name
- `service`: "consul-mesh-metrics" (our ServiceMonitor)

## Troubleshooting

### Dashboard shows "No data"
1. **Check namespace variable**: Must be set to `tracing-demo`
2. **Check service variable**: Must be one of the 7 services
3. **Verify metrics exist**:
   ```bash
   kubectl exec -n openshift-user-workload-monitoring prometheus-user-workload-0 -c prometheus -- \
     wget -qO- 'http://localhost:9090/api/v1/query?query=envoy_cluster_upstream_rq_total{namespace="tracing-demo"}' | \
     jq '.data.result | length'
   ```
   Should return a number > 0

### Service dropdown is empty
1. **Verify namespace is set to "tracing-demo"**
2. **Check if metrics have local_cluster label**:
   ```bash
   kubectl exec -n openshift-user-workload-monitoring prometheus-user-workload-0 -c prometheus -- \
     wget -qO- 'http://localhost:9090/api/v1/query?query=envoy_cluster_upstream_rq_total{namespace="tracing-demo"}' | \
     jq '.data.result[].metric.local_cluster' | sort -u
   ```
   Should show: cart, catalog, checkout, frontend, inventory, payment, zipkin

### Metrics show 0 values
This is normal if there's no traffic. Generate traffic:
```bash
cd loadtest
./simple-load.sh
```

## Alternative: Query Metrics Directly

If the dashboard variables are confusing, you can query metrics directly in Grafana's Explore view:

1. Go to Grafana → Explore
2. Select datasource: Prometheus
3. Enter query:
   ```promql
   sum(rate(envoy_cluster_upstream_rq_total{namespace="tracing-demo"}[5m])) by (local_cluster)
   ```
4. Click "Run query"

This will show request rates for all services without needing to configure variables.

## Dashboard Variable Query Improvements (Optional)

If you want to improve the namespace variable to only show namespaces with Consul services, you could modify the dashboard JSON:

**Current namespace query:**
```
label_values(container_memory_working_set_bytes{job="kubernetes-nodes-cadvisor"},namespace)
```

**Better query:**
```
label_values(envoy_cluster_upstream_rq_total, namespace)
```

This would only show namespaces that have Envoy metrics.

To make this change:
1. Go to Dashboard Settings (gear icon)
2. Click "Variables"
3. Click "namespace"
4. Change the query
5. Save dashboard

---

**Quick Start:**
1. Open dashboard from Consul UI
2. Set namespace = `tracing-demo`
3. Set service = `cart` (or any service)
4. Run `cd loadtest && ./simple-load.sh`
5. Watch metrics populate! 🎉