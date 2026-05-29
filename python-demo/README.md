# Python Zipkin Distributed Tracing Demo

A minimal three-service Python demo that shows **end-to-end distributed tracing** with [Zipkin](https://zipkin.io/) using the [`py-zipkin`](https://pypi.org/project/py-zipkin/) library.

## Service call chain

```
client
  └─► service-a (port 8091)   ← entry point
        └─► service-b (port 8092)
              └─► service-c (port 8093)   ← end of chain
```

Each service creates a span and propagates [B3 trace-context headers](https://github.com/openzipkin/b3-propagation) to the next hop so that all three spans appear as a single distributed trace in the Zipkin UI.

## Files

| File | Purpose |
|---|---|
| `tracing.py` | Shared `HttpTransport` class and encoding constant used by all three services |
| `service_a.py` | Entry-point service; starts a new trace root span |
| `service_b.py` | Middle service; continues the trace as a child span |
| `service_c.py` | End service; continues the trace as a grandchild span |
| `requirements.txt` | Python dependencies (`Flask`, `requests`, `py-zipkin`) |
| `Dockerfile` | Single image used by all three Python services |
| `charts/python-demo/` | Helm chart that deploys Zipkin + the three services on Kubernetes |

## Quick start

### 1. Build the application image

```bash
cd python-demo
docker build -t py-zipkin-demo:latest .
```

For local clusters, make sure the image is available to the cluster runtime:

```bash
# kind example
kind load docker-image py-zipkin-demo:latest

# or minikube example
minikube image load py-zipkin-demo:latest
```

### 2. Install the Helm chart

```bash
helm upgrade --install python-demo charts/python-demo
```

This installs four Deployments and four Services:

- Zipkin (`python-demo-zipkin`)
- service-a (`python-demo-service-a`)
- service-b (`python-demo-service-b`)
- service-c (`python-demo-service-c`)

### 3. Port-forward service-a and trigger a trace

In one terminal:

```bash
kubectl port-forward svc/python-demo-service-a 8091:8091
```

In another terminal:

```bash
curl http://localhost:8091/demo
```

Expected JSON response:

```json
{
  "service": "service-a",
  "message": "Trace complete! Open Zipkin UI to inspect the distributed trace.",
  "chain": {
    "service": "service-b",
    "downstream": {
      "service": "service-c",
      "message": "Work done at the end of the chain."
    }
  }
}
```

### 4. Inspect traces in Zipkin

In another terminal:

```bash
kubectl port-forward svc/python-demo-zipkin 9411:9411
```

Open [http://localhost:9411](http://localhost:9411) in your browser.

1. Click **Run Query** (the default query finds recent traces).
2. Select the trace with **service-a** as the root service.
3. You will see three spans forming a chain:
   - `service-a : GET /demo`
     - `service-b : GET /work`
       - `service-c : GET /work`

## Health endpoints

Each service exposes a `/health` endpoint. Port-forward each service before curl:

```bash
kubectl port-forward svc/python-demo-service-a 8091:8091
curl http://localhost:8091/health   # service-a

kubectl port-forward svc/python-demo-service-b 8092:8092
curl http://localhost:8092/health   # service-b

kubectl port-forward svc/python-demo-service-c 8093:8093
curl http://localhost:8093/health   # service-c
```

## Environment variables

All services read configuration from environment variables:

| Variable | Default | Description |
|---|---|---|
| `SERVICE_NAME` | `service-a/b/c` | Name reported to Zipkin |
| `PORT` | `8091 / 8092 / 8093` | Listening port |
| `ZIPKIN_URL` | `http://python-demo-zipkin:9411/api/v2/spans` | Zipkin collector endpoint |
| `SERVICE_B_URL` | `http://python-demo-service-b:8092` | service-a → service-b URL |
| `SERVICE_C_URL` | `http://python-demo-service-c:8093` | service-b → service-c URL |

## Running without Docker

```bash
# Install dependencies
pip install -r requirements.txt

# In three separate terminals:
ZIPKIN_URL=http://localhost:9411/api/v2/spans python service_c.py
ZIPKIN_URL=http://localhost:9411/api/v2/spans python service_b.py
ZIPKIN_URL=http://localhost:9411/api/v2/spans python service_a.py

# Trigger a trace
curl http://localhost:8091/demo
```

You will also need a locally running Zipkin instance, e.g.:

```bash
docker run -d -p 9411:9411 openzipkin/zipkin
```

## Helm chart configuration

The chart is in `charts/python-demo` and can be customized with `values.yaml` overrides.

Common overrides:

- `image.repository`
- `image.tag`
- `zipkin.service.type`
- `services.serviceA|serviceB|serviceC.service.type`

Example install using an image from a registry:

```bash
helm upgrade --install python-demo charts/python-demo \
  --set image.repository=ghcr.io/acme/py-zipkin-demo \
  --set image.tag=v1.0.0
```

## Multi-architecture image builds

The `Dockerfile` supports both `linux/amd64` and `linux/arm64`. Build and push a multi-arch image with `docker buildx`:

```bash
# One-time setup: create and activate a multi-platform builder
docker buildx create --name multiarch --use

# Build and push both platforms to a registry
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --tag <your-registry>/py-zipkin-demo:latest \
  --push \
  .
```

> **Note:** pushing to a registry is required when building for multiple platforms simultaneously, because a local Docker daemon can only store one platform image per tag at a time.

## How B3 propagation works

1. **service-a** creates a root span (new `trace_id`, new `span_id`).
2. Before calling service-b, it reads the current span from py-zipkin's thread-local storage and injects it as B3 HTTP headers (`X-B3-TraceId`, `X-B3-SpanId`, `X-B3-Sampled`).
3. **service-b** extracts those headers into a `ZipkinAttrs` object and passes it as `zipkin_attrs` to `zipkin_span`. py-zipkin uses the incoming `span_id` as the `parent_span_id` of service-b's new span, keeping the same `trace_id`.
4. **service-c** does the same with the headers forwarded by service-b.
5. All three spans share the same `trace_id` and form a parent→child→grandchild hierarchy visible in the Zipkin UI.
