# Zipkin OpenTelemetry Microdemo - Current Project Status

**Last Updated**: 2026-05-15  
**Status**: Active demo application with working Consul mesh deployment; observability documentation consolidated around the standalone Prometheus + Grafana workflow in [`deploy/observability/README.md`](deploy/observability/README.md)

## What This Project Is

[`zipkin-otel-microdemo`](README.md) is a Go microservices demo packaged as a Helm chart for Kubernetes/OpenShift. It demonstrates:

- distributed tracing with Zipkin
- service-to-service communication across multiple application services
- Consul service mesh integration
- topology, metrics, and dashboard deep links from the Consul UI

## Deployed Application Services

- `frontend` — public entrypoint
- `catalog` — product catalog
- `cart` — shopping cart
- `checkout` — order orchestration
- `payment` — payment simulation
- `inventory` — stock simulation
- `zipkin` — trace collector and UI

## Canonical Documentation

Use these files as the current source of truth:

- [`README.md`](README.md) — project overview, app deployment, load generation, and core references
- [`deploy/observability/README.md`](deploy/observability/README.md) — canonical observability deployment and Grafana/Prometheus workflow
- [`CONSUL_TOPOLOGY.md`](CONSUL_TOPOLOGY.md) — topology configuration and service dependency model
- [`CONSUL_METRICS.md`](CONSUL_METRICS.md) — Consul UI metrics configuration concepts and verification
- [`CONSUL_INTENTIONS.md`](CONSUL_INTENTIONS.md) — service intention guidance
- [`loadtest/README.md`](loadtest/README.md) — supported traffic generation tools

Historical troubleshooting and superseded implementation notes live under [`docs/archive/`](docs/archive/README.md).

## Current Observability Direction

The canonical observability path for this repo is:

1. Deploy the app from [`charts/zipkin-otel-microdemo/`](charts/zipkin-otel-microdemo)
2. Configure Consul and Prometheus/Grafana using [`deploy/observability/README.md`](deploy/observability/README.md)
3. Patch Grafana dashboards for Consul deep-link variables using:
   - [`deploy/observability/fix-grafana-dashboard.sh`](deploy/observability/fix-grafana-dashboard.sh)
   - [`deploy/observability/patch-dashboard-consul-vars.py`](deploy/observability/patch-dashboard-consul-vars.py)
4. Generate **mesh-aware** traffic using [`loadtest/mesh-load.sh`](loadtest/mesh-load.sh)

## Important Current Notes

### 1. Do not treat older sidecar/UWM guidance as canonical

Some historical documents in this repo describe a Prometheus sidecar or OpenShift user-workload monitoring path as the final solution. Those notes are historical only and should not be treated as the current source of truth for this repository.

### 2. Dashboard source of truth comes from upstream workflow

For Consul UI deep-link dashboards, this repo should stay aligned with the upstream workflow documented in [`../learn-consul-proxy-metrics/README.md`](../learn-consul-proxy-metrics/README.md), especially the downloaded upstream dashboard + local patching model.

### 3. Traffic must go through the mesh

For topology and Envoy metrics validation, use mesh-aware traffic generation. Route-based traffic can bypass the dataplane path needed for some metrics and topology validation.

Preferred command:

```bash
cd loadtest
./mesh-load.sh
```

## What Is Consolidated vs Historical

### Active / current
- app source in [`cmd/`](cmd)
- Helm chart in [`charts/zipkin-otel-microdemo/`](charts/zipkin-otel-microdemo)
- observability workflow in [`deploy/observability/`](deploy/observability)
- root docs that describe current app behavior and operator workflow

### Historical / troubleshooting reference
- one-off investigation summaries
- obsolete “final solution” notes from earlier metrics iterations
- narrow Grafana fix notes once superseded by the patching workflow
- root-level debug markdown that has been moved or should be treated as archive material

## Recommended Reading Order

1. [`README.md`](README.md)
2. [`deploy/observability/README.md`](deploy/observability/README.md)
3. [`CONSUL_TOPOLOGY.md`](CONSUL_TOPOLOGY.md)
4. [`CONSUL_METRICS.md`](CONSUL_METRICS.md)
5. [`loadtest/README.md`](loadtest/README.md)

## Current Cleanup Assessment

The main repo cleanup need is not application code but documentation and operational script sprawl. The current consolidation goal is:

- keep one clear current-state story at the repo root
- keep observability implementation details under [`deploy/observability/`](deploy/observability)
- keep historical debugging notes under [`docs/archive/`](docs/archive/README.md)
- reduce duplicate or contradictory “working solution” documents

## Operational Reality Check

At the time of this update:

- service-defaults work has been addressed in-repo
- stale troubleshooting documentation has already been partially archived
- remaining cleanup work is primarily documentation alignment and removal of contradictory guidance
- live topology/metrics validation still depends on generating fresh mesh traffic and confirming current Prometheus label/query behavior

## Short Version

If you need to understand where the project stands:

- the **app and Helm chart are usable**
- the **observability path should follow [`deploy/observability/README.md`](deploy/observability/README.md)**
- the **archive contains old attempts and should not be treated as current design**