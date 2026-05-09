# zipkin-otel-microdemo

A field-demo quality Go microservices application for demonstrating distributed tracing with Zipkin, designed to run on Consul Enterprise Service Mesh.

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

## Request Flows

1. **Browse products**: `frontend → catalog`
2. **Add to cart**: `frontend → cart → catalog`
3. **Checkout**: `frontend → checkout → cart → inventory → payment`

## Running Locally

### Prerequisites

- Go 1.21+
- Docker and Docker Compose
- (Optional) k6 for load testing

### Quick Start

```bash
docker-compose up
```

### Build and run without Docker

```bash
go build ./...

SERVICE_NAME=catalog  go run ./cmd/catalog &
SERVICE_NAME=cart     CATALOG_URL=http://localhost:8081 go run ./cmd/cart &
SERVICE_NAME=inventory go run ./cmd/inventory &
SERVICE_NAME=payment  go run ./cmd/payment &
SERVICE_NAME=checkout CART_URL=http://localhost:8082 \
                      INVENTORY_URL=http://localhost:8085 \
                      PAYMENT_URL=http://localhost:8084 \
                      go run ./cmd/checkout &
SERVICE_NAME=frontend CATALOG_URL=http://localhost:8081 \
                      CART_URL=http://localhost:8082 \
                      CHECKOUT_URL=http://localhost:8083 \
                      go run ./cmd/frontend
```

### Viewing Traces

Open http://localhost:9411 for the Zipkin UI.

## Environment Variables

### Common to all services

| Variable      | Default                                    | Description                     |
|---------------|--------------------------------------------|---------------------------------|
| `SERVICE_NAME`| (binary name)                              | Zipkin local service name       |
| `PORT`        | see per-service default                    | Listening port                  |
| `ZIPKIN_URL`  | `http://localhost:9411/api/v2/spans`       | Zipkin HTTP reporter endpoint   |
| `SAMPLE_RATE` | `1.0`                                      | Trace sample rate (0.0 – 1.0)  |

### frontend

| Variable       | Default                   |
|----------------|---------------------------|
| `CATALOG_URL`  | `http://localhost:8081`   |
| `CART_URL`     | `http://localhost:8082`   |
| `CHECKOUT_URL` | `http://localhost:8083`   |

### cart

| Variable      | Default                  |
|---------------|--------------------------|
| `CATALOG_URL` | `http://localhost:8081`  |

### checkout

| Variable        | Default                  |
|-----------------|--------------------------|
| `CART_URL`      | `http://localhost:8082`  |
| `INVENTORY_URL` | `http://localhost:8085`  |
| `PAYMENT_URL`   | `http://localhost:8084`  |

### payment

| Variable               | Default | Description                                |
|------------------------|---------|--------------------------------------------|
| `PAYMENT_FAILURE_RATE` | `0.02`  | Fraction of requests to decline (0–1)      |
| `PAYMENT_LATENCY_MS`   | `50`    | Mean extra latency in ms (±30% jitter)     |

### inventory

| Variable                    | Default | Description                               |
|-----------------------------|---------|-------------------------------------------|
| `INVENTORY_CONTENTION_RATE` | `0.05`  | Fraction of reservations to fail (0–1)    |

## Demo Controls

Inject faults at runtime without restarting services:

```bash
# 30% payment failures
curl -X POST http://localhost:8084/admin/config \
  -H 'Content-Type: application/json' \
  -d '{"failure_rate":0.3,"latency_ms":50}'

# Slow payment simulation (500 ms mean)
curl -X POST http://localhost:8084/admin/config \
  -H 'Content-Type: application/json' \
  -d '{"failure_rate":0.02,"latency_ms":500}'
```

Or set via environment variables before starting:

```bash
PAYMENT_FAILURE_RATE=0.3       # 30% payment failures
PAYMENT_LATENCY_MS=500         # slow payments
INVENTORY_CONTENTION_RATE=0.2  # frequent stock issues
```

## Load Testing with k6

```bash
k6 run loadtest/k6/script.js
```

Or against a specific target:

```bash
k6 run -e BASE_URL=http://localhost:8080 loadtest/k6/script.js
```

The script runs three weighted scenarios:

| Flow         | Weight | Steps                                         |
|--------------|--------|-----------------------------------------------|
| Browse       | 55%    | `GET /products` → `GET /products/{id}`        |
| Add to cart  | 25%    | `GET /products` → `POST /cart/{user}/items`   |
| Checkout     | 20%    | Add items → `POST /checkout`                  |

## Consul Enterprise Service Mesh Integration

### Envoy proxy spans and app spans

When deployed behind Consul Connect (Envoy), each service receives two spans per request:

1. **Envoy ingress span** – created by the sidecar proxy for inbound traffic.
2. **App span** – created by `pkg/tracing` server middleware.

Because both Envoy and zipkin-go respect **B3 single/multi-header propagation**, the app span automatically becomes a child of the Envoy ingress span. The resulting trace shows both infrastructure-level (proxy) and application-level timing in a single Zipkin trace.

### B3 propagation

All inter-service calls use `zipkin-go/middleware/http` which injects **B3 multi-headers** (`X-B3-TraceId`, `X-B3-SpanId`, `X-B3-ParentSpanId`, `X-B3-Sampled`). Envoy's default Zipkin tracing configuration also uses B3 multi-headers, so no additional translation is needed.

### Sampling configuration

The `SAMPLE_RATE` environment variable controls the application-level sampler. When running behind Envoy:

- Set `SAMPLE_RATE=1.0` (head-based: sample everything) – let Envoy or Consul control the sampling decision upstream.
- Set `SAMPLE_RATE=0.1` for 10% sampling in high-traffic environments.

The application respects the `X-B3-Sampled: 0` header: if the upstream proxy decides not to sample, zipkin-go will also not report spans.
