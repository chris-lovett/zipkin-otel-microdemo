# Service Monitoring

This section covers service and mesh monitoring for workloads running with Consul dataplane.

## What to Monitor

Primary data plane and service signals:
- request rate, error rate, and latency between services
- active connections and rejected connections
- per-service traffic direction and topology edges
- resource usage in service pods

## Required Configuration

Use:
- [service-defaults.yaml](../../service-defaults.yaml)
- [deploy/observability/prometheus-values.yaml](../../deploy/observability/prometheus-values.yaml)
- [deploy/observability/podmonitor-consul-proxy-metrics.yaml](../../deploy/observability/podmonitor-consul-proxy-metrics.yaml) for Prometheus Operator path

Key requirements:
- dataplane metrics exposed on port 20200
- Prometheus scrape annotations present on injected pods
- service protocol defaults configured for HTTP-aware topology metrics

## Verification

Run:
- [scripts/observability/diagnose-envoy-metrics.sh](../../scripts/observability/diagnose-envoy-metrics.sh)
- [scripts/observability/diagnose-topology.sh](../../scripts/observability/diagnose-topology.sh)

Generate in-mesh traffic:
- [loadtest/mesh-load.sh](../../loadtest/mesh-load.sh)

Expected outcome:
- Envoy metrics series present in Prometheus
- Consul topology shows active edges and traffic values under load

## Related

- [../../CONSUL_TOPOLOGY.md](../../CONSUL_TOPOLOGY.md)
- [../../CONSUL_METRICS.md](../../CONSUL_METRICS.md)
