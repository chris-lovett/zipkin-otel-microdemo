# Control Plane Monitoring

This section covers monitoring of Consul server health and control plane behavior.

## What to Monitor

Key control plane signals:
- raft health and leadership stability
- autopilot health
- server request and RPC metrics
- member count and server availability

## Required Configuration

Use these files:
- [deploy/observability/consul-values-observability.yaml](../../deploy/observability/consul-values-observability.yaml)
- [deploy/observability/prometheus-values.yaml](../../deploy/observability/prometheus-values.yaml)

The primary requirement for control plane metrics in this repository:
- Prometheus must scrape Consul servers over HTTPS with ACL bearer token support

## Verification

Run:
- [scripts/observability/check-consul-metrics.sh](../../scripts/observability/check-consul-metrics.sh)
- [scripts/observability/diagnose-consul-metrics.sh](../../scripts/observability/diagnose-consul-metrics.sh)

Expected outcome:
- consul-servers scrape target is up
- queries for raft and autopilot metrics return series

## Common Failure Modes

- missing ACL token mount in Prometheus
- TLS scrape mismatch on server endpoint
- wrong namespace or labels in scrape discovery
- stale dashboard datasource UID

## Related

- [Operations and Troubleshooting](05-operations-and-troubleshooting.md)
- [deploy/observability/README.md](../../deploy/observability/README.md)
