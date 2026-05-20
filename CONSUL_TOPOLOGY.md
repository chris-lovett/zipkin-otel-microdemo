# Consul Service Mesh Topology Graph Configuration

This document explains how the Helm chart is configured to populate the Consul UI topology graph and how to verify it's working correctly.

## Overview

The Consul UI topology view requires **explicit upstream declarations** via pod annotations. While transparent proxy mode allows traffic to flow without declaring upstreams, Consul's topology graph feature needs them to build the service dependency map.

## Service Dependency Map

```
frontend
├── catalog (port 8081)
├── cart (port 8082)
└── checkout (port 8083)

cart
└── catalog (port 8081)

checkout
├── cart (port 8082)
├── inventory (port 8085)
└── payment (port 8084)

catalog (leaf service - no upstreams)
payment (leaf service - no upstreams)
inventory (leaf service - no upstreams)
```

## Helm Chart Configuration

### values.yaml

Each service that calls downstream services has a `consulUpstreams` field:

```yaml
services:
  frontend:
    consulUpstreams: "catalog:8081,cart:8082,checkout:8083"
    # ... other config

  cart:
    consulUpstreams: "catalog:8081"
    # ... other config

  checkout:
    consulUpstreams: "cart:8082,inventory:8085,payment:8084"
    # ... other config

  # Leaf services (catalog, payment, inventory) have no consulUpstreams
```

### templates/services.yaml

The template automatically adds Consul annotations to pod metadata:

```yaml
metadata:
  annotations:
    consul.hashicorp.com/connect-inject: "true"
    consul.hashicorp.com/transparent-proxy: "true"
    {{- if $svc.consulUpstreams }}
    consul.hashicorp.com/connect-service-upstreams: {{ $svc.consulUpstreams | quote }}
    {{- end }}
```

## Deployment

### Initial Deployment

```bash
cd /Users/chrislovett/hashi/monitoring/tracing/zipkin-otel-microdemo

# Deploy with Helm
helm upgrade --install zipkin-demo \
  ./charts/zipkin-otel-microdemo \
  --namespace tracing-demo \
  --create-namespace
```

### Upgrading Existing Deployment

If you already have the app deployed without upstream annotations:

```bash
# Upgrade the Helm release
helm upgrade zipkin-demo \
  ./charts/zipkin-otel-microdemo \
  --namespace tracing-demo

# Restart all pods to pick up new annotations
kubectl rollout restart deployment -n tracing-demo
```

## Verification

### 1. Check Pod Annotations

Verify that pods have the correct Consul annotations:

```bash
# Check frontend pod annotations
kubectl get pod -n tracing-demo -l app.kubernetes.io/name=frontend -o yaml | grep -A5 annotations

# Expected output should include:
# consul.hashicorp.com/connect-inject: "true"
# consul.hashicorp.com/transparent-proxy: "true"
# consul.hashicorp.com/connect-service-upstreams: "catalog:8081,cart:8082,checkout:8083"
```

### 2. Verify Consul Service Registration

Check that services are registered with upstreams in Consul:

```bash
# Get Consul server pod name
CONSUL_POD=$(kubectl get pod -n consul -l component=server -o jsonpath='{.items[0].metadata.name}')

# Check frontend service registration
kubectl exec -it $CONSUL_POD -n consul -- \
  consul catalog services -tags

# Check service-defaults config for frontend
kubectl exec -it $CONSUL_POD -n consul -- \
  consul config read -kind service-defaults -name frontend
```

### 3. View Topology in Consul UI

1. **Access Consul UI:**
   ```bash
   # Port-forward to Consul UI
   kubectl port-forward -n consul svc/consul-ui 8500:443
   ```
   
   Then open: https://localhost:8500

2. **Navigate to Topology:**
   - Go to **Services** in the left menu
   - Click on any service (e.g., `frontend`)
   - Click the **Topology** tab
   - You should see a visual graph showing upstream and downstream services

3. **Expected Topology Views:**

   **Frontend Service:**
   - Should show 3 upstreams: catalog, cart, checkout
   - Should show 0 downstreams (it's the entry point)

   **Cart Service:**
   - Should show 1 upstream: catalog
   - Should show 2 downstreams: frontend, checkout

   **Checkout Service:**
   - Should show 3 upstreams: cart, inventory, payment
   - Should show 1 downstream: frontend

   **Catalog Service:**
   - Should show 0 upstreams (leaf service)
   - Should show 2 downstreams: frontend, cart

### 4. Generate Traffic to Populate Metrics

The topology graph is more useful with traffic flowing, but for this repo you should prefer **mesh-aware** traffic generation so the dataplane path and Envoy metrics are actually exercised.

```bash
cd loadtest

# Preferred: generate in-mesh traffic
./mesh-load.sh
```

If you use other load generators, verify they still exercise the mesh path you want to observe. Route-based traffic can be useful for app demos, but it is less reliable for validating Consul topology and Envoy metrics in this repository.

After generating traffic, the topology view should begin to show:
- Request rates between services
- Success/error rates
- Latency metrics

## Troubleshooting

Use the canonical observability troubleshooting flow in [`deploy/observability/README.md`](deploy/observability/README.md) and script entrypoints in [`scripts/observability/`](scripts/observability/). Keep the checks below only for topology-specific validation.

### Topology Graph is Empty

**Problem:** Services appear in Consul but topology graph is empty.

**Solution:**
1. Verify pod annotations include `connect-service-upstreams`
2. Restart pods to pick up new annotations: `kubectl rollout restart deployment -n tracing-demo`
3. Run `make observability-verify`
4. Wait 30-60 seconds for Consul to sync

### Services Not Showing Upstreams

**Problem:** Services registered but upstreams not visible.

**Check:**
```bash
# Verify the annotation is present
kubectl get pod -n tracing-demo -l app.kubernetes.io/name=frontend -o jsonpath='{.items[0].metadata.annotations.consul\.hashicorp\.com/connect-service-upstreams}'

# Should output: catalog:8081,cart:8082,checkout:8083
```

If missing, the Helm chart may not have been upgraded properly. Re-run:
```bash
helm upgrade zipkin-demo ./charts/zipkin-otel-microdemo --namespace tracing-demo
kubectl rollout restart deployment -n tracing-demo
make observability-verify
```

### Consul UI Shows "Topology Unavailable"

**Problem:** Topology tab shows "This feature is not available" message.

**Possible Causes:**
1. **Consul Community Edition:** Topology view requires Consul Enterprise
2. **UI Config Disabled:** Check Consul server configuration

**Verify Consul Edition:**
```bash
kubectl exec -it $CONSUL_POD -n consul -- consul version
```

**Check UI Config:**
```bash
kubectl exec -it $CONSUL_POD -n consul -- consul info | grep -i ui
```

## Why Explicit Upstreams Matter

| Feature | Transparent Proxy Only | With Explicit Upstreams |
|---------|----------------------|------------------------|
| Traffic routing | ✅ Works | ✅ Works |
| mTLS enforcement | ✅ Works | ✅ Works |
| Topology UI graph | ❌ Not populated | ✅ Populated |
| Intentions enforcement | Partial | ✅ Full |
| Service dependencies visible | ❌ No | ✅ Yes |
| Metrics per upstream | ❌ Limited | ✅ Detailed |

## Additional Resources

- [Consul Service Mesh Documentation](https://developer.hashicorp.com/consul/docs/connect)
- [Consul Topology View](https://developer.hashicorp.com/consul/docs/connect/observability/ui-visualization)
- [Connect Service Upstreams Annotation](https://developer.hashicorp.com/consul/docs/k8s/annotations-and-labels#consul-hashicorp-com-connect-service-upstreams)

## Related Files

- [`values.yaml`](charts/zipkin-otel-microdemo/values.yaml) - Service upstream configuration
- [`templates/services.yaml`](charts/zipkin-otel-microdemo/templates/services.yaml) - Annotation template
- [`README.md`](README.md) - Main deployment documentation
- [`loadtest/README.md`](loadtest/README.md) - Load testing documentation