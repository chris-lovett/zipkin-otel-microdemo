# Consul Observability Manual

This manual is the primary guide for configuring observability with Consul in this repository.

Audience:
- platform and SRE operators
- application teams running services in Consul service mesh

Scope:
- Consul control plane monitoring and logging
- service and mesh data plane monitoring
- distributed tracing integration and verification
- operational troubleshooting runbooks

## Start Here

1. [Control Plane Monitoring](01-control-plane-monitoring.md)
2. [Service Monitoring](02-service-monitoring.md)
3. [Logging](03-logging.md)
4. [Distributed Tracing](04-distributed-tracing.md)
5. [Operations and Troubleshooting](05-operations-and-troubleshooting.md)

## Implementation Assets

Core implementation resources are in:
- [deploy/observability](../../deploy/observability/README.md)
- [scripts/observability](../../scripts/observability)
- [loadtest](../../loadtest/README.md)

## Canonical Operating Model

This repository supports two metrics collection modes:

1. Standalone Prometheus in namespace observability (primary)
2. Prometheus Operator with PodMonitor in OpenShift (optional)

Do not combine sidecar-based historical scrape patterns with the primary model.

## Success Criteria

A healthy observability deployment in this repository means:
- Consul UI topology shows active service edges during load
- Prometheus has Envoy and Consul server series for expected targets
- Grafana dashboards open from Consul with service and namespace scoping
- Control plane and data plane logs are queryable
- Trace spans are visible and correlated with service traffic
