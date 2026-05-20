# zipkin-otel-microdemo

A field-demo quality Go microservices application for demonstrating distributed tracing with Zipkin, now packaged for Kubernetes/OpenShift using a single Helm chart.

## 📚 Documentation

- **[docs/observability/README.md](docs/observability/README.md)** - Complete Consul observability manual (start here)
- **[DEMO_GUIDE.md](DEMO_GUIDE.md)** - 🎯 **Step-by-step demo script** for showcasing distributed tracing with Zipkin
- **[PROJECT_STATUS.md](PROJECT_STATUS.md)** - Current project status and documentation map
- **[deploy/observability/README.md](deploy/observability/README.md)** - Implementation guide for Prometheus/Grafana manifests and scripts
- **[CONSUL_TOPOLOGY.md](CONSUL_TOPOLOGY.md)** - Service mesh topology configuration and verification
- **[CONSUL_INTENTIONS.md](CONSUL_INTENTIONS.md)** - Service-to-service authorization policies
- **[CONSUL_METRICS.md](CONSUL_METRICS.md)** - Consul UI metrics concepts and verification guidance
- **[service-defaults.yaml](service-defaults.yaml)** - Consul ServiceDefaults for HTTP protocol detection in topology metrics
- **[scripts/observability/](scripts/observability/)** - Canonical diagnose/fix/troubleshoot scripts
- **[loadtest/README.md](loadtest/README.md)** - Load testing tools and scenarios
- **[docs/archive/README.md](docs/archive/README.md)** - Historical troubleshooting and superseded implementation notes

## Observability Manual Scope

This repository is a practical manual for setting up and operating observability with Consul across:
- control plane monitoring
- service and mesh monitoring
- logging for Consul and applications
- distributed tracing and verification
- operations runbooks and troubleshooting

Primary manual entrypoint:
- [`docs/observability/README.md`](docs/observability/README.md)

## Observability Operator Flow (OpenShift-first)

Use one canonical Prometheus path at a time:

1. Primary: standalone Prometheus (`prometheus-server`) configured via `deploy/observability/prometheus-values.yaml`
2. Optional: Prometheus Operator/OpenShift monitoring using `deploy/observability/podmonitor-consul-proxy-metrics.yaml`

Do not mix old sidecar-based scrape patterns with the canonical flow above.

Operator commands:

```bash
make observability-verify
make observability-troubleshoot
make observability-sync-dashboards
```

### Consul UI Metrics Runbook (Procedure)

Use this sequence when topology metrics are empty or Grafana deep links show no data:

1. Run baseline verification:

```bash
make observability-verify
```

2. Generate in-mesh traffic so topology windows have live data:

```bash
cd loadtest
./mesh-load.sh
```

3. Re-check troubleshooting diagnostics if metrics remain empty:

```bash
make observability-troubleshoot
```

4. Reconcile dashboard JSON and request GrafanaDashboard resync:

```bash
make observability-sync-dashboards
```

5. Validate Consul UI Topology and Open Dashboard behavior:
- service edges show non-zero values during traffic
- Open Dashboard links open with service/namespace scope already applied

Conceptual model and pass/fail verification criteria are maintained in [`CONSUL_METRICS.md`](CONSUL_METRICS.md).

Root legacy docs remain for historical context only. For superseded implementation details and prior troubleshooting paths, use [`docs/archive/README.md`](docs/archive/README.md).

## Architecture

```
                    ┌───────────────────────────────────────────────────┐
  Browser / k6 ───▶ │  frontend :8080                                   │
                    └──────┬──────────────────┬───────────────────┬─────┘
                           │                  │                   │
                    ┌──────▼──────┐    ┌──────▼──────┐    ┌──────▼──────┐
                    │ catalog     │    │ cart        │    │ checkout    │
                    │ :8081       │◀───│ :8082       │    │ :8083       │
                    └─────────────┘    └─────────────┘    └──┬─────┬───┘
                                                             │     │
                                                       ┌─────▼───┐ │
                                                       │inventory│ │
                                                       │ :8085   │ │
                                                       └─────────┘ │
                                                              ┌─────▼───┐
                                                              │payment  │
                                                              │ :8084   │
                                                              └─────────┘
```

## Services

| Service   | Port | Description                              |
|-----------|------|------------------------------------------|
| frontend  | 8080 | Public API gateway                       |
| catalog   | 8081 | Product catalog                          |
| cart      | 8082 | Shopping cart (in-memory)                |
| checkout  | 8083 | Purchase orchestrator                    |
| payment   | 8084 | Payment processing (injectable faults)   |
| inventory | 8085 | Stock management (contention simulation) |
| zipkin    | 9411 | Trace collector and UI                   |

## Deploying to OpenShift with Helm

### Prerequisites

- OpenShift cluster access (`oc login`)
- Helm 3
- Docker or Podman (for image builds)
- Access to a container registry

### 1) Build and publish service images

This repository includes a single multi-stage `Dockerfile` and Make targets for all app services.

#### Multi-Architecture Build (Recommended for OpenShift)

Build images for both AMD64 and ARM64 architectures:

```bash
# Configure registry (default: quay.io/chris_lovett/zipkin-otel-microdemo)
export IMAGE_REGISTRY=quay.io/<your-org>/zipkin-otel-microdemo
export IMAGE_TAG=0.1.0

# Build and push multi-arch images
make build-multiarch
```

This builds and pushes multi-architecture images supporting:
- `linux/amd64` (Intel/AMD processors)
- `linux/arm64` (ARM processors, Apple Silicon)

#### Single Architecture Build

For local development or single-architecture deployments:

```bash
export IMAGE_REGISTRY=quay.io/<your-org>/zipkin-otel-microdemo
export IMAGE_TAG=0.1.0

make build-images
make push-images
```

Both methods build/push:

- `${IMAGE_REGISTRY}/frontend:${IMAGE_TAG}`
- `${IMAGE_REGISTRY}/catalog:${IMAGE_TAG}`
- `${IMAGE_REGISTRY}/cart:${IMAGE_TAG}`
- `${IMAGE_REGISTRY}/checkout:${IMAGE_TAG}`
- `${IMAGE_REGISTRY}/payment:${IMAGE_TAG}`
- `${IMAGE_REGISTRY}/inventory:${IMAGE_TAG}`

### 2) Configure runtime/deployment via `values.yaml`

All runtime/deployment settings are controlled in `charts/zipkin-otel-microdemo/values.yaml`, including:

- image registry/tags
- imagePullSecrets for private registries
- service ports and env vars
- dependency wait behavior
- OpenShift Route and optional Ingress exposure

If needed, override values inline with `--set` (no environment-specific values files are required).

### 3) Create namespace and configure image pull secrets (if using private registry)

```bash
# Create namespace
kubectl create namespace tracing-demo

# If using private registry (e.g., Quay.io), create pull secret
kubectl create secret docker-registry quay-pull \
  --docker-server=quay.io \
  --docker-username=<your-username> \
  --docker-password=<your-password> \
  -n tracing-demo

# Update values.yaml to reference the secret
# global:
#   imagePullSecrets:
#     - name: quay-pull
```

### 4) Install or upgrade

```bash
helm upgrade --install zipkin-demo \
  ./charts/zipkin-otel-microdemo \
  -n tracing-demo \
  --set global.imageRegistry=quay.io/<your-org>/zipkin-otel-microdemo
```

For Consul Service Mesh integration, the chart is pre-configured with:
- `consul.hashicorp.com/connect-inject: "true"` - Enables automatic sidecar injection
- `consul.hashicorp.com/transparent-proxy: "true"` - Enables transparent proxy mode
- `consul.hashicorp.com/connect-service-upstreams` - Explicit upstream declarations for topology graph
- Individual ServiceAccounts per service (required for Consul ACL authentication)

**📖 For detailed Consul topology graph configuration and verification, see [CONSUL_TOPOLOGY.md](CONSUL_TOPOLOGY.md)**

**📖 For the current observability deployment and Grafana/Prometheus workflow, see [deploy/observability/README.md](deploy/observability/README.md)**

### 4a) Apply Consul ServiceDefaults for HTTP-aware topology metrics

Consul's richer topology metrics depend on L7 protocol awareness. Apply [`service-defaults.yaml`](service-defaults.yaml) so the mesh knows these services speak HTTP:

```bash
kubectl apply -f service-defaults.yaml
```

This creates [`ServiceDefaults`](service-defaults.yaml) resources for:
- `frontend`
- `catalog`
- `cart`
- `checkout`
- `payment`
- `inventory`

After applying, restart the app deployments so proxies pick up the updated service configuration:

```bash
kubectl rollout restart deployment -n tracing-demo
kubectl rollout status deployment/frontend -n tracing-demo
```

Then generate fresh in-mesh traffic:

```bash
cd loadtest
./mesh-load.sh
```

Wait 1-2 minutes, then refresh the Consul topology view and any Grafana dashboards linked from the Consul UI. Prefer [`mesh-load.sh`](loadtest/mesh-load.sh) over route-based load generators when validating topology or Envoy metrics.

### 5) Access the app

With OpenShift Routes enabled (default):

```bash
oc get route frontend
oc get route zipkin
```

Use the `frontend` route for app traffic and `zipkin` route for trace UI.

## Exploring Distributed Traces in Zipkin

### Accessing Zipkin UI

Get the Zipkin route URL:
```bash
oc get route zipkin -n tracing-demo
```

Open the URL in your browser (e.g., `https://zipkin-tracing-demo.apps.rosa.cluster1.6cxo.p3.openshiftapps.com`)

### Generating Trace Data

#### Quick Manual Tests

Generate individual traces with curl:

```bash
# Get frontend URL
FRONTEND_URL=$(oc get route frontend -n tracing-demo -o jsonpath='{.spec.host}')

# Browse products (simple trace)
curl https://$FRONTEND_URL/products

# Get specific product (2-service trace: frontend → catalog)
curl https://$FRONTEND_URL/products/1

# Add to cart (3-service trace: frontend → cart → catalog)
curl -X POST https://$FRONTEND_URL/cart/user123/items \
  -H 'Content-Type: application/json' \
  -d '{"product_id":"1","quantity":2}'

# Checkout (complex 5-service trace: frontend → checkout → cart → inventory + payment)
curl -X POST https://$FRONTEND_URL/checkout \
  -H 'Content-Type: application/json' \
  -d '{"user_id":"user123"}'
```

#### Load Testing Tools

For generating more interesting distributed traces, use the included load testing tools:

**Simple Bash Load Generator** (no dependencies):
```bash
cd loadtest
./simple-load.sh
```

**Advanced Python Load Generator** (with scenarios and statistics):
```bash
cd loadtest
# Mixed traffic (default)
./advanced-load.py

# Browse-heavy traffic
./advanced-load.py --scenario browse --users 10 --duration 120

# Purchase-heavy traffic
./advanced-load.py --scenario buy --users 5 --duration 90

# Spike traffic
./advanced-load.py --scenario spike --users 20 --duration 30
```

**k6 Professional Load Testing**:
```bash
cd loadtest
k6 run -e BASE_URL=https://frontend-tracing-demo.apps.rosa.cluster1.6cxo.p3.openshiftapps.com k6/script.js
```

See [`loadtest/README.md`](loadtest/README.md) for detailed documentation on all load testing tools, scenarios, and usage examples.

### Zipkin UI Queries

#### 1. View All Recent Traces
- Click "RUN QUERY" on the main page
- Shows all traces from the last 15 minutes
- Each trace represents one request through the system

#### 2. Find Traces by Service
- **Service Name** dropdown → Select `frontend`
- Click "RUN QUERY"
- Shows all traces that passed through the frontend service

#### 3. Find Slow Traces
- **Min Duration** → Enter `100ms` (or `100000` microseconds)
- Click "RUN QUERY"
- Identifies performance bottlenecks

#### 4. Find Checkout Flows
- **Service Name** → `checkout`
- Click "RUN QUERY"
- Shows complete purchase flows through all services

#### 5. Find Traces with Errors
- **Tags** → Add tag `error=true`
- Click "RUN QUERY"
- Shows failed requests (useful when payment failures are injected)

### Understanding Trace Details

Click on any trace to see:

1. **Service Dependency Graph** (top)
   - Visual representation of service calls
   - Shows which services communicated
   - Displays call counts between services

2. **Trace Timeline** (middle)
   - Waterfall view of all spans
   - Each bar represents time spent in a service
   - Nested spans show parent-child relationships

3. **Span Details** (click any span)
   - **Service name** - Which service created this span
   - **Operation** - HTTP method and endpoint (e.g., `GET /products`)
   - **Duration** - Time spent in this span
   - **Tags** - Metadata like HTTP status, method, URL
   - **Annotations** - Timing events within the span

### Consul Service Mesh Spans

With Consul Service Mesh enabled, each service call shows **two spans**:

1. **Envoy Ingress Span** (e.g., `ingress catalog`)
   - Created by the Consul sidecar proxy
   - Shows time spent in the Envoy proxy
   - Includes mTLS handshake overhead

2. **Application Span** (e.g., `GET /products`)
   - Created by the application code
   - Shows actual business logic execution time
   - Child of the Envoy span

This dual-span pattern helps identify:
- Network/proxy overhead vs application logic time
- mTLS performance impact
- Service mesh routing behavior

### Example Trace Patterns

**Simple Product Browse:**
```
frontend (GET /products)
  └─> catalog (GET /products)
```

**Add to Cart:**
```
frontend (POST /cart/{user}/items)
  └─> cart (POST /items)
      └─> catalog (GET /products/{id})
```

**Complete Checkout:**
```
frontend (POST /checkout)
  └─> checkout (POST /checkout)
      ├─> cart (GET /cart/{user})
      ├─> inventory (POST /reserve)
      └─> payment (POST /process)
```

### Tracing Implementation Details

All services use `zipkin-go` library with:
- **HTTP Server Middleware** - Automatically creates spans for incoming requests
- **HTTP Client Middleware** - Propagates trace context to downstream services
- **B3 Propagation** - Compatible with Consul/Envoy tracing
- **100% Sampling** - All requests are traced (configurable via `SAMPLE_RATE`)

Tracing is enabled on all HTTP endpoints:
- `GET /products` - List products
- `GET /products/{id}` - Get product details
- `POST /cart/{user}/items` - Add to cart
- `GET /cart/{user}` - Get cart contents
- `POST /checkout` - Process checkout
- `POST /inventory/reserve` - Reserve inventory
- `POST /payment/process` - Process payment

### 6) Uninstall

```bash
helm uninstall microdemo
```

## Request Flows

1. **Browse products**: `frontend → catalog`
2. **Add to cart**: `frontend → cart → catalog`
3. **Checkout**: `frontend → checkout → cart → inventory → payment`

## Runtime Configuration

### Common to all services

| Variable      | Default (chart)                           | Description                     |
|---------------|-------------------------------------------|---------------------------------|
| `SERVICE_NAME`| service key from `values.yaml`            | Zipkin local service name       |
| `PORT`        | per-service value from `values.yaml`      | Listening port                  |
| `ZIPKIN_URL`  | `http://zipkin:9411/api/v2/spans`         | Zipkin HTTP reporter endpoint   |
| `SAMPLE_RATE` | `1.0`                                     | Trace sample rate (0.0 – 1.0)  |

### Service-specific defaults

The chart's `values.yaml` includes the same compose-era defaults for:

- `CATALOG_URL`, `CART_URL`, `CHECKOUT_URL`
- `INVENTORY_URL`, `PAYMENT_URL`
- `PAYMENT_FAILURE_RATE`, `PAYMENT_LATENCY_MS`
- `INVENTORY_CONTENTION_RATE`

## Demo Controls

Inject payment faults at runtime:

```bash
curl -X POST http://<payment-host>/admin/config \
  -H 'Content-Type: application/json' \
  -d '{"failure_rate":0.3,"latency_ms":50}'
```

Set these values under each service's `env` section in `charts/zipkin-otel-microdemo/values.yaml`:

```yaml
services:
  payment:
    env:
      PAYMENT_FAILURE_RATE: "0.3"
      PAYMENT_LATENCY_MS: "500"
  inventory:
    env:
      INVENTORY_CONTENTION_RATE: "0.2"
```

## Load Testing with k6

```bash
k6 run -e BASE_URL=https://<frontend-route-host> loadtest/k6/script.js
```

The script runs three weighted scenarios:

| Flow         | Weight | Steps                                         |
|--------------|--------|-----------------------------------------------|
| Browse       | 55%    | `GET /products` → `GET /products/{id}`        |
| Add to cart  | 25%    | `GET /products` → `POST /cart/{user}/items`   |
| Checkout     | 20%    | Add items → `POST /checkout`                  |

## Local Development (optional)

Docker Compose remains available for local-only workflows:

```bash
docker-compose up
```

You can also run each service directly with `go run` as before.

## Consul Service Mesh Integration

This application is designed to work seamlessly with Consul Service Mesh on OpenShift/Kubernetes.

### Automatic Sidecar Injection

The Helm chart includes Consul annotations for automatic sidecar injection:

```yaml
annotations:
  consul.hashicorp.com/connect-inject: "true"
  consul.hashicorp.com/transparent-proxy: "true"
```

When deployed to a namespace with Consul Service Mesh enabled, each pod automatically receives:
- **Consul Dataplane sidecar** - Envoy proxy for service-to-service communication
- **Init container** - Configures iptables for transparent proxy mode

### Service Registration

Each service is automatically registered in Consul with:
- Service name matching the Kubernetes service
- Health checks integrated with Kubernetes readiness/liveness probes
- Sidecar proxy registration for mTLS communication

Verify registration:
```bash
kubectl exec -it consul-server-0 -n consul -- consul catalog services
```

### mTLS and Security

All service-to-service communication is automatically encrypted with mutual TLS:
- Certificates managed by Consul
- Automatic certificate rotation
- No application code changes required
- Zero-trust security model

### Distributed Tracing with Envoy

When deployed with Consul Service Mesh, each request generates two spans:

1. **Envoy ingress span** – Created by the sidecar proxy for inbound traffic
2. **Application span** – Created by `pkg/tracing` server middleware

Both Envoy and the application respect **B3 propagation headers**, ensuring the application span becomes a child of the Envoy span in the trace hierarchy.

### B3 Propagation

All inter-service calls use `zipkin-go/middleware/http` which injects **B3 multi-headers**:
- `X-B3-TraceId` - Unique trace identifier
- `X-B3-SpanId` - Current span identifier
- `X-B3-ParentSpanId` - Parent span identifier
- `X-B3-Sampled` - Sampling decision

This ensures complete trace context propagation through both Envoy proxies and application code.

### Sampling Configuration

The `SAMPLE_RATE` environment variable (default: `1.0`) controls application-level sampling. Set to `1.0` for 100% sampling in demo environments.

### NetworkPolicy Considerations

When deploying with NetworkPolicies enabled, ensure:
- Pods can reach Consul server (ports 8501, 8502, 8301, 8300)
- DNS resolution is allowed (port 53/5353 to openshift-dns namespace)
- Inter-service communication within namespace is permitted

Example NetworkPolicy files are included in the repository for reference.

### Metrics and observability (standalone Prometheus)

Envoy metrics are exposed on **port 20200** on each injected pod. Standalone Prometheus in the `observability` namespace scrapes them directly (no per-pod Prometheus sidecar).

See **[deploy/observability/README.md](deploy/observability/README.md)** for Helm values, Grafana datasource, and migration steps off OpenShift user-workload monitoring.

### Verifying Consul Integration

Check that all pods have 2/2 containers ready (app + sidecar):
```bash
kubectl get pods -n tracing-demo
```

Expected output:
```
NAME                         READY   STATUS    RESTARTS   AGE
cart-xxx                     2/2     Running   0          5m
catalog-xxx                  2/2     Running   0          5m
checkout-xxx                 2/2     Running   0          5m
frontend-xxx                 2/2     Running   0          5m
inventory-xxx                2/2     Running   0          5m
payment-xxx                  2/2     Running   0          5m
zipkin-xxx                   2/2     Running   0          5m
```

View service mesh topology in Consul UI or check service registrations:
```bash
kubectl exec -it consul-server-0 -n consul -- consul catalog services
```
