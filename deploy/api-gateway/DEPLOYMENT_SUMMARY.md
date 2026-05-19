# Consul API Gateway Deployment Summary

## Overview

Successfully deployed Consul API Gateway to the tracing-demo namespace with Prometheus monitoring integration.

## Components Deployed

### 1. Gateway Infrastructure

- **GatewayClass**: `consul-api-gateway` (cluster-scoped)
  - Configured with metrics enabled on port 20200
  - Path: `/metrics`
  - Service type: ClusterIP

- **Gateway**: `api-gateway` (namespace: tracing-demo)
  - Listener on port 8080 (HTTP)
  - AWS ELB provisioned: `a7f8fdd7b4cee4a84940bd1d39b06f1e-1271446744.us-east-2.elb.amazonaws.com`
  - Status: Programmed and Ready

- **HTTPRoute**: `frontend-route`
  - Routes all traffic (/) to frontend service on port 8080

### 2. Monitoring Configuration

- **Prometheus Scrape Config**: Added `consul-api-gateway` job
  - Discovers API Gateway pods via Kubernetes SD
  - Filters by `component=api-gateway` label
  - Scrapes metrics from port 20200 at path `/metrics`
  - Relabels job to `consul-api-gateway` for dashboard compatibility

- **Pod Annotations**: API Gateway pod includes:
  ```yaml
  prometheus.io/scrape: "true"
  prometheus.io/port: "20200"
  prometheus.io/path: "/metrics"
  ```

### 3. Dashboard Integration

- **Gateway Health Dashboard**: Already deployed and configured
  - Dashboard UID: `platform-gateway-health`
  - Queries use `job="consul-api-gateway"` filter
  - Metrics include:
    - Request rate: `envoy_http_downstream_rq_total`
    - Error rates by response code class
    - Response times and latencies
    - Active connections
    - Upstream cluster health

## Deployment Files

```
deploy/api-gateway/
├── gateway-class.yaml          # GatewayClass and GatewayClassConfig
├── gateway.yaml                # Gateway and HTTPRoute resources
├── servicemonitor.yaml         # ServiceMonitor (not used - standalone Prometheus)
├── podmonitor.yaml             # PodMonitor (not used - standalone Prometheus)
├── prometheus-scrape-config.yaml  # Reference scrape configuration
├── add-scrape-config.sh        # Script to add scrape config to Prometheus
└── README.md                   # Deployment and verification guide
```

## Verification Steps

### 1. Check Gateway Status
```bash
kubectl get gateway -n tracing-demo
kubectl get httproute -n tracing-demo
kubectl get pods -n tracing-demo -l component=api-gateway
```

### 2. Test API Gateway
```bash
# Port-forward to test locally
kubectl port-forward -n tracing-demo svc/api-gateway 8080:8080

# Test the route
curl http://localhost:8080/products
```

### 3. Verify Prometheus Scraping
```bash
# Port-forward to Prometheus
kubectl port-forward -n observability svc/prometheus-server 9090:80

# Visit http://localhost:9090/targets
# Look for job="consul-api-gateway"
```

### 4. Check Metrics in Prometheus
```bash
# Query for API Gateway metrics
curl 'http://localhost:9090/api/v1/query?query=envoy_http_downstream_rq_total{job="consul-api-gateway"}'
```

### 5. View Dashboard in Grafana
```bash
# Port-forward to Grafana
kubectl port-forward -n observability svc/grafana 3000:80

# Visit http://localhost:3000
# Navigate to "Gateway Health" dashboard
```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     AWS Load Balancer                        │
│  a7f8fdd7b4cee4a84940bd1d39b06f1e-1271446744.us-east-2...  │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│              Consul API Gateway (Envoy)                      │
│  - Port 8080: HTTP traffic                                   │
│  - Port 20200: Prometheus metrics                            │
│  - Annotations: prometheus.io/scrape=true                    │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                   Frontend Service                           │
│                   (port 8080)                                │
└─────────────────────────────────────────────────────────────┘

Monitoring Flow:
┌──────────────┐    scrapes     ┌─────────────────┐
│  Prometheus  │ ──────────────▶│  API Gateway    │
│              │  port 20200    │  (Envoy metrics)│
└──────┬───────┘                └─────────────────┘
       │
       │ queries
       ▼
┌──────────────┐
│   Grafana    │
│  Dashboard   │
└──────────────┘
```

## Metrics Available

The API Gateway exposes Envoy metrics including:

- **Request Metrics**:
  - `envoy_http_downstream_rq_total` - Total requests
  - `envoy_http_downstream_rq_xx` - Requests by response code class (2xx, 3xx, 4xx, 5xx)
  - `envoy_http_downstream_rq_time_bucket` - Request duration histogram

- **Connection Metrics**:
  - `envoy_cluster_upstream_cx_active` - Active upstream connections
  - `envoy_cluster_upstream_cx_total` - Total upstream connections

- **Cluster Health**:
  - `envoy_cluster_membership_healthy` - Healthy cluster members
  - `envoy_cluster_membership_total` - Total cluster members

## Troubleshooting

### No Metrics in Dashboard

1. **Check Prometheus Target**:
   ```bash
   kubectl port-forward -n observability svc/prometheus-server 9090:80
   # Visit http://localhost:9090/targets
   # Look for consul-api-gateway job
   ```

2. **Verify Pod Annotations**:
   ```bash
   kubectl get pod -n tracing-demo -l component=api-gateway -o yaml | grep -A 5 "annotations:"
   ```

3. **Test Metrics Endpoint**:
   ```bash
   POD=$(kubectl get pods -n tracing-demo -l component=api-gateway -o jsonpath='{.items[0].metadata.name}')
   kubectl exec -n tracing-demo $POD -- wget -qO- http://localhost:20200/metrics | head -20
   ```

### Gateway Not Routing Traffic

1. **Check Gateway Status**:
   ```bash
   kubectl describe gateway api-gateway -n tracing-demo
   ```

2. **Check HTTPRoute Status**:
   ```bash
   kubectl describe httproute frontend-route -n tracing-demo
   ```

3. **Check Pod Logs**:
   ```bash
   kubectl logs -n tracing-demo -l component=api-gateway --tail=50
   ```

## Next Steps

1. **Generate Traffic**: Use load testing tools to generate traffic through the API Gateway
   ```bash
   cd loadtest
   ./mesh-load.sh
   ```

2. **Monitor Dashboard**: Watch the Gateway Health dashboard populate with metrics

3. **Configure Alerts**: Set up Prometheus alerts for API Gateway health

4. **Add More Routes**: Extend the HTTPRoute configuration to expose additional services

## References

- [Consul API Gateway Documentation](https://developer.hashicorp.com/consul/docs/api-gateway)
- [Gateway Health Dashboard](../../../gateway-health-dashboard.json)
- [Prometheus Configuration](prometheus-scrape-config.yaml)