# Zipkin OpenTelemetry Microdemo - Project Status

**Last Updated**: 2026-05-15  
**Status**: ✅ OPERATIONAL - Metrics and monitoring fully functional

## Quick Links

- **Main Documentation**: [`README.md`](README.md)
- **Consul Topology**: [`CONSUL_TOPOLOGY.md`](CONSUL_TOPOLOGY.md)
- **Consul Intentions**: [`CONSUL_INTENTIONS.md`](CONSUL_INTENTIONS.md)
- **Load Testing**: [`loadtest/README.md`](loadtest/README.md)

## Current Architecture

### Deployed Services (7 total)
- **frontend** (8080) - Public API gateway
- **catalog** (8081) - Product catalog
- **cart** (8082) - Shopping cart
- **checkout** (8083) - Purchase orchestrator
- **payment** (8084) - Payment processing
- **inventory** (8085) - Stock management
- **zipkin** (9411) - Trace collector and UI

### Infrastructure Components
- **Consul Service Mesh** - mTLS, service discovery, traffic management
- **Prometheus** (OpenShift User Workload Monitoring) - Metrics collection
- **Grafana** - Metrics visualization
- **Zipkin** - Distributed tracing

## Metrics Solution (FINAL)

### Implementation: Prometheus Sidecar Pattern

Each application pod runs **3 containers**:
1. **Application container** - The microservice
2. **consul-dataplane** - Envoy sidecar (metrics on localhost:20200)
3. **prometheus-sidecar** - Scrapes localhost:20200, exposes on 0.0.0.0:9090

### Why This Solution

**Problem**: consul-dataplane binds metrics endpoint to `127.0.0.1:20200` (localhost only), making it inaccessible to external Prometheus.

**Solution**: Prometheus sidecar runs in the same pod, can access localhost, and exposes metrics externally on port 9090 for the main Prometheus to scrape.

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│ Each Pod (7 total)                                              │
│                                                                 │
│  ┌──────────────┐  ┌──────────────────┐  ┌─────────────────┐  │
│  │ Application  │  │ consul-dataplane │  │ prometheus-     │  │
│  │ Container    │  │                  │  │ sidecar         │  │
│  │              │  │ Metrics:         │  │                 │  │
│  │              │  │ 127.0.0.1:20200  │  │ Scrapes:        │  │
│  │              │  │ (localhost only) │◄─┤ localhost:20200 │  │
│  │              │  │                  │  │                 │  │
│  │              │  │ 5,105 Envoy      │  │ Exposes:        │  │
│  │              │  │ metrics          │  │ 0.0.0.0:9090    │  │
│  └──────────────┘  └──────────────────┘  └─────────────────┘  │
│                                                    │            │
└────────────────────────────────────────────────────┼────────────┘
                                                     │ /federate
                                                     ▼
                                    ┌────────────────────────────┐
                                    │ Prometheus User Workload   │
                                    │ (OpenShift)                │
                                    │                            │
                                    │ Scrapes all 7 pods via     │
                                    │ ServiceMonitor             │
                                    └────────────────────────────┘
```

### OpenShift-Specific Configuration

**Critical Labels Required**:
- Namespace: `openshift.io/user-monitoring=true`
- ServiceMonitor: `openshift.io/user-monitoring=true`

**Why**: OpenShift separates cluster monitoring from user workload monitoring. User-workload Prometheus only discovers ServiceMonitors with the correct label.

### Verification Commands

```bash
# Check all pods have 3/3 containers
kubectl get pods -n tracing-demo

# Check Prometheus targets (should show 7 pods as "up")
kubectl exec -n openshift-user-workload-monitoring prometheus-user-workload-0 -c prometheus -- \
  wget -qO- 'http://localhost:9090/api/v1/targets' | \
  jq '.data.activeTargets[] | select(.labels.namespace=="tracing-demo")'

# Query metrics
kubectl exec -n openshift-user-workload-monitoring prometheus-user-workload-0 -c prometheus -- \
  wget -qO- 'http://localhost:9090/api/v1/query?query=envoy_cluster_upstream_rq_total{namespace="tracing-demo"}' | \
  jq '.data.result | length'
```

## Grafana Dashboard Configuration

### Status: ✅ WORKING

**Dashboard**: "Data Plane Performance" (UID: `data-plane-performance`)

**Access URLs**:
- Direct: `https://grafana-observability.apps.rosa.cluster1.6cxo.p3.openshiftapps.com`
- Dashboard: `https://grafana-observability.apps.rosa.cluster1.6cxo.p3.openshiftapps.com/d/data-plane-performance/data-plane-performance`
- With namespace: `...?var-namespace=tracing-demo`

**Credentials**: admin / changeme123

### Namespace Variable Fix Applied

**Problem**: Namespace dropdown was empty because the query used `container_memory_working_set_bytes` which wasn't accessible.

**Solution**: Changed to `label_values(envoy_cluster_upstream_rq_total, namespace)` which uses our available Envoy metrics.

### Using the Dashboard

1. Open dashboard URL
2. Set **namespace** = `tracing-demo`
3. Set **service** = any service (cart, catalog, etc.)
4. Generate traffic: `cd loadtest && ./mesh-load.sh`
5. Watch metrics populate

## Traffic Generation (CRITICAL)

### ⚠️ Important: Use Mesh-Aware Load Test

**WRONG** (bypasses mesh):
```bash
./simple-load.sh  # Uses external Route, no Envoy metrics
```

**CORRECT** (flows through mesh):
```bash
./mesh-load.sh    # Uses kubectl exec, generates Envoy metrics
```

### Why This Matters

The original `simple-load.sh` accessed services via OpenShift Routes, which bypass Envoy sidecars entirely. No Envoy traffic = no metrics.

The `mesh-load.sh` script executes requests from inside pods, ensuring all traffic flows through Consul Service Mesh and generates metrics.

## Consul UI Metrics

### Status: ✅ WORKING

Consul UI displays metrics from Prometheus including:
- Request rates (RPS)
- Error rates
- Latency (P50, P95, P99)
- Service topology with traffic flow

**Configuration**: See [`CONSUL_METRICS.md`](CONSUL_METRICS.md) for detailed setup.

## Known Issues & Solutions

### Issue: "No Metrics Available" in Consul UI

**Cause**: No traffic flowing through the mesh

**Solution**:
```bash
cd loadtest
./mesh-load.sh
```

Wait 1-2 minutes for metrics to populate.

### Issue: Grafana Shows "No data"

**Causes**:
1. Wrong namespace selected (must be "tracing-demo")
2. No traffic (run mesh-load.sh)
3. Wrong time range (try "Last 1 hour")

**Solution**: Set namespace variable, generate traffic, adjust time range.

### Issue: Prometheus Targets Show "DOWN"

**Cause**: Usually NetworkPolicy blocking traffic or pods not ready

**Solution**:
```bash
# Check pod status
kubectl get pods -n tracing-demo

# Check NetworkPolicies
kubectl get networkpolicy -n tracing-demo

# Verify ServiceMonitor labels
kubectl get servicemonitor -n tracing-demo consul-mesh-metrics -o yaml | grep openshift.io
```

## Files Structure

### Active Documentation
- [`README.md`](README.md) - Main project documentation
- [`PROJECT_STATUS.md`](PROJECT_STATUS.md) - This file (current status)
- [`CONSUL_TOPOLOGY.md`](CONSUL_TOPOLOGY.md) - Service mesh topology configuration
- [`CONSUL_INTENTIONS.md`](CONSUL_INTENTIONS.md) - Service-to-service authorization
- [`CONSUL_METRICS.md`](CONSUL_METRICS.md) - Consul UI metrics configuration
- [`loadtest/README.md`](loadtest/README.md) - Load testing documentation

### Archived Documentation (Historical Reference)
See [`docs/archive/`](docs/archive/) for historical troubleshooting documents from the metrics implementation process.

## Deployment Commands

### Initial Deployment
```bash
# Create namespace
kubectl create namespace tracing-demo

# Install with Helm
helm upgrade --install zipkin-demo \
  ./charts/zipkin-otel-microdemo \
  -n tracing-demo \
  --set global.imageRegistry=quay.io/<your-org>/zipkin-otel-microdemo
```

### Verify Deployment
```bash
# Check pods (should be 3/3 containers)
kubectl get pods -n tracing-demo

# Check services
kubectl get svc -n tracing-demo

# Check routes
oc get route -n tracing-demo
```

### Generate Traffic
```bash
cd loadtest
./mesh-load.sh
```

### Access UIs
```bash
# Get URLs
oc get route frontend -n tracing-demo
oc get route zipkin -n tracing-demo

# Grafana (if configured)
echo "https://grafana-observability.apps.rosa.cluster1.6cxo.p3.openshiftapps.com"
```

## Metrics Available

### Envoy Metrics (5,105 total)
- `envoy_cluster_upstream_rq_total` - Total requests
- `envoy_cluster_upstream_rq_time_bucket` - Request latency histogram
- `envoy_cluster_upstream_cx_active` - Active connections
- `envoy_http_downstream_rq_total` - HTTP requests
- Plus 5,100+ other Envoy metrics

### Metric Labels
- `namespace`: "tracing-demo"
- `local_cluster`: Service name (cart, catalog, etc.)
- `consul_source_service`: Consul service name
- `pod`: Pod name
- `service`: "consul-mesh-metrics"

## Success Criteria

- ✅ 7/7 pods running with 3/3 containers
- ✅ 7/7 Prometheus targets with health "up"
- ✅ 5,105 Envoy metrics being scraped
- ✅ Metrics queryable in Prometheus
- ✅ Consul UI displays service metrics
- ✅ Grafana dashboards show data
- ✅ Zipkin traces show Envoy + application spans

## Support & Troubleshooting

For detailed troubleshooting, see archived documentation in [`docs/archive/`](docs/archive/):
- Historical metrics fixes
- OpenShift-specific configurations
- Dashboard troubleshooting
- Root cause analyses

## Timeline

- **2026-05-14**: Metrics solution implemented (Prometheus sidecar pattern)
- **2026-05-14**: OpenShift monitoring labels configured
- **2026-05-14**: Grafana dashboard namespace variable fixed
- **2026-05-14**: Load test corrected to use mesh-aware approach
- **2026-05-15**: Documentation consolidated

## Next Steps

1. **For Demos**: Run `./mesh-load.sh` before showing metrics
2. **For Development**: Use the working solution as-is
3. **For Production**: Consider upgrading Consul to version that supports bind address configuration
4. **For Optimization**: Monitor sidecar resource usage, adjust if needed

---

**Status**: Ready for customer presentations and demonstrations.