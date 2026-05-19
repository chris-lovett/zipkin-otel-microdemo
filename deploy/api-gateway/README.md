# Consul API Gateway Deployment

This directory contains the configuration for deploying Consul API Gateway to provide ingress to the tracing demo application.

## Components

1. **gateway-class.yaml** - Defines the GatewayClass and GatewayClassConfig
   - Enables metrics on port 20200
   - Configures deployment parameters

2. **gateway.yaml** - Deploys the API Gateway instance
   - Creates Gateway resource in tracing-demo namespace
   - Configures HTTPRoute to route traffic to frontend service

3. **servicemonitor.yaml** - Prometheus ServiceMonitor
   - Scrapes metrics from API Gateway on port 20200
   - Labels metrics with job="consul-api-gateway"

## Deployment

Deploy in order:

```bash
# 1. Create GatewayClass (cluster-scoped)
kubectl apply -f gateway-class.yaml

# 2. Deploy Gateway and HTTPRoute
kubectl apply -f gateway.yaml

# 3. Configure Prometheus monitoring
kubectl apply -f servicemonitor.yaml
```

## Verification

Check Gateway status:
```bash
kubectl get gateway -n tracing-demo
kubectl get httproute -n tracing-demo
```

Check API Gateway pods:
```bash
kubectl get pods -n tracing-demo -l api-gateway.consul.hashicorp.com/managed=true
```

Verify metrics endpoint:
```bash
kubectl port-forward -n tracing-demo <api-gateway-pod> 20200:20200
curl http://localhost:20200/metrics | grep envoy
```

Check Prometheus targets:
```bash
# Port-forward to Prometheus
kubectl port-forward -n observability svc/prometheus-server 9090:80

# Visit http://localhost:9090/targets
# Look for "consul-api-gateway" job
```

## Testing

Access the frontend through the API Gateway:
```bash
# Get the Gateway service
kubectl get svc -n tracing-demo -l api-gateway.consul.hashicorp.com/managed=true

# Port-forward to test
kubectl port-forward -n tracing-demo svc/api-gateway 8080:8080

# Test the route
curl http://localhost:8080/products
```

## Metrics

The API Gateway exposes Envoy metrics on port 20200 including:
- `envoy_http_downstream_rq_total` - Total requests
- `envoy_http_downstream_rq_xx` - Requests by response code class
- `envoy_http_downstream_rq_time` - Request duration
- `envoy_cluster_upstream_cx_active` - Active connections

These metrics are used by the Gateway Health dashboard in Grafana.