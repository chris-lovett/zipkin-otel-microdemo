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
| `Dockerfile` | Single image used by all three Compose services |
| `docker-compose.yml` | Starts Zipkin + the three services |

## Quick start

### 1. Start everything with Docker Compose

```bash
cd python-demo
docker compose up --build
```

Docker Compose uses [BuildKit](https://docs.docker.com/build/buildkit/) automatically (Docker 23+).  
The `Dockerfile` and `docker-compose.yml` declare `platforms: [linux/amd64, linux/arm64]`, so the image is built for your host architecture by default and is compatible with both x86-64 and Apple Silicon / ARM servers.

All four containers (Zipkin + 3 services) will start on the `py-demo-network` bridge.

### 2. Trigger the demo trace

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

### 3. Inspect the trace in Zipkin

Open [http://localhost:9411](http://localhost:9411) in your browser.

1. Click **Run Query** (the default query finds recent traces).
2. Select the trace with **service-a** as the root service.
3. You will see three spans forming a chain:
   - `service-a : GET /demo`
     - `service-b : GET /work`
       - `service-c : GET /work`

## Health endpoints

Each service exposes a `/health` endpoint:

```bash
curl http://localhost:8091/health   # service-a
curl http://localhost:8092/health   # service-b
curl http://localhost:8093/health   # service-c
```

## Environment variables

All services read configuration from environment variables:

| Variable | Default | Description |
|---|---|---|
| `SERVICE_NAME` | `service-a/b/c` | Name reported to Zipkin |
| `PORT` | `8091 / 8092 / 8093` | Listening port |
| `ZIPKIN_URL` | `http://localhost:9411/api/v2/spans` | Zipkin collector endpoint |
| `SERVICE_B_URL` | `http://localhost:8092` | service-a → service-b URL |
| `SERVICE_C_URL` | `http://localhost:8093` | service-b → service-c URL |

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

## Multi-architecture builds

The `Dockerfile` and `docker-compose.yml` are configured for multi-architecture support (`linux/amd64` and `linux/arm64`).

### Local development (single platform)

`docker compose up --build` automatically builds for the host machine's native architecture. No extra steps are needed on either Intel/AMD or Apple Silicon machines.

### Building for both platforms simultaneously (e.g. for CI or a registry push)

Use `docker buildx` with a multi-platform builder:

```bash
# One-time setup: create and activate a multi-platform builder
docker buildx create --name multiarch --use

# Build and push both platforms to a registry
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --tag <your-registry>/py-zipkin-demo:latest \
  --push \
  python-demo/
```

Or use `docker buildx bake` with the Compose file:

```bash
cd python-demo
docker buildx bake --push
```

> **Note:** pushing to a registry is required when building for multiple platforms simultaneously, because a local Docker daemon can only store one platform image per tag at a time. For local development on your own machine `docker compose up --build` is sufficient.

## How B3 propagation works

1. **service-a** creates a root span (new `trace_id`, new `span_id`).
2. Before calling service-b, it reads the current span from py-zipkin's thread-local storage and injects it as B3 HTTP headers (`X-B3-TraceId`, `X-B3-SpanId`, `X-B3-Sampled`).
3. **service-b** extracts those headers into a `ZipkinAttrs` object and passes it as `zipkin_attrs` to `zipkin_span`. py-zipkin uses the incoming `span_id` as the `parent_span_id` of service-b's new span, keeping the same `trace_id`.
4. **service-c** does the same with the headers forwarded by service-b.
5. All three spans share the same `trace_id` and form a parent→child→grandchild hierarchy visible in the Zipkin UI.
