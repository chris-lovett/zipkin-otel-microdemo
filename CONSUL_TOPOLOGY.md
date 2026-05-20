# Consul Topology - Concepts and Verification

This document provides topology concepts and verification checkpoints.

For operational setup and procedures, use:
- [docs/observability/02-service-monitoring.md](docs/observability/02-service-monitoring.md)
- [deploy/observability/README.md](deploy/observability/README.md)

## Service Dependency Model

Expected upstream relationships:
- frontend -> catalog, cart, checkout
- cart -> catalog
- checkout -> cart, inventory, payment
- catalog, payment, inventory are leaf services

## What Topology Depends On

1. Consul injection and upstream annotations are present.
2. Service defaults are configured for HTTP-aware metrics.
3. Prometheus is scraping dataplane metrics from injected workloads.
4. In-mesh traffic exists during the observation window.

## Verification Criteria

A healthy topology state means:
- expected upstream and downstream edges are visible
- edge metrics become non-zero during active load
- edge relationships match service dependency intent

## Failure Patterns

Typical causes when topology looks wrong:
- missing upstream annotations
- missing or stale service defaults entries
- scrape namespace mismatch in Prometheus or PodMonitor selectors
- no mesh traffic in recent window

## Related

- [CONSUL_METRICS.md](CONSUL_METRICS.md)
- [docs/observability/README.md](docs/observability/README.md)
- [scripts/observability/diagnose-topology.sh](scripts/observability/diagnose-topology.sh)
- [docs/archive/README.md](docs/archive/README.md)
