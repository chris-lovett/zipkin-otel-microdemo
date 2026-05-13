# zipkin-otel-microdemo

A field-demo quality Go microservices application for demonstrating distributed tracing with Zipkin, now packaged for Kubernetes/OpenShift using a single Helm chart.

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

This repository now includes a single multi-stage `Dockerfile` and Make targets for all app services:

```bash
# Optional overrides
export IMAGE_REGISTRY=ghcr.io/<your-org>/zipkin-otel-microdemo
export IMAGE_TAG=0.1.0

make build-images
make push-images
```

By default this builds/pushes:

- `${IMAGE_REGISTRY}/frontend:${IMAGE_TAG}`
- `${IMAGE_REGISTRY}/catalog:${IMAGE_TAG}`
- `${IMAGE_REGISTRY}/cart:${IMAGE_TAG}`
- `${IMAGE_REGISTRY}/checkout:${IMAGE_TAG}`
- `${IMAGE_REGISTRY}/payment:${IMAGE_TAG}`
- `${IMAGE_REGISTRY}/inventory:${IMAGE_TAG}`

### 2) Configure runtime/deployment via `values.yaml`

All runtime/deployment settings are controlled in `charts/zipkin-otel-microdemo/values.yaml`, including:

- image registry/tags
- service ports and env vars
- dependency wait behavior
- OpenShift Route and optional Ingress exposure

If needed, override values inline with `--set` (no environment-specific values files are required).

### 3) Install or upgrade

```bash
helm upgrade --install microdemo \
  ./charts/zipkin-otel-microdemo \
  --set global.imageRegistry=ghcr.io/<your-org>/zipkin-otel-microdemo \
  --set services.frontend.image.tag=0.1.0 \
  --set services.catalog.image.tag=0.1.0 \
  --set services.cart.image.tag=0.1.0 \
  --set services.checkout.image.tag=0.1.0 \
  --set services.payment.image.tag=0.1.0 \
  --set services.inventory.image.tag=0.1.0
```

### 4) Access the app

With OpenShift Routes enabled (default):

```bash
oc get route frontend
oc get route zipkin
```

Use the `frontend` route for app traffic and `zipkin` route for trace UI.

### 5) Uninstall

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

## Consul Enterprise Service Mesh Integration

### Envoy proxy spans and app spans

When deployed behind Consul Connect (Envoy), each service receives two spans per request:

1. **Envoy ingress span** – created by the sidecar proxy for inbound traffic.
2. **App span** – created by `pkg/tracing` server middleware.

Because both Envoy and zipkin-go respect **B3 single/multi-header propagation**, the app span automatically becomes a child of the Envoy ingress span.

### B3 propagation

All inter-service calls use `zipkin-go/middleware/http` which injects **B3 multi-headers** (`X-B3-TraceId`, `X-B3-SpanId`, `X-B3-ParentSpanId`, `X-B3-Sampled`).

### Sampling configuration

The `SAMPLE_RATE` environment variable controls the application-level sampler.
