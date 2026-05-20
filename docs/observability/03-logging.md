# Logging

This section covers logs for Consul control plane and mesh-enabled applications.

## Logging Scope

Control plane logs:
- Consul servers
- connect injector
- telemetry collector
- mesh gateways

Application and data plane logs:
- app container logs
- consul-dataplane and Envoy logs

## Log Stack in This Repository

Available implementation assets:
- [deploy/observability/loki-values.yaml](../../deploy/observability/loki-values.yaml)
- [deploy/observability/promtail-values.yaml](../../deploy/observability/promtail-values.yaml)
- [deploy/observability/loki-datasource.yaml](../../deploy/observability/loki-datasource.yaml)
- [deploy/observability/envoy-app-logs-dashboard.yaml](../../deploy/observability/envoy-app-logs-dashboard.yaml)

## What Good Looks Like

- control plane pods emit logs without repeated ACL or TLS errors
- application logs and dataplane logs are queryable by namespace and pod
- Grafana log dashboards resolve expected labels and streams

## Verification

Quick checks:
- confirm Loki datasource in Grafana
- query logs for consul namespace and tracing-demo namespace
- verify Envoy log panels return data during mesh load

## Related

- [Operations and Troubleshooting](05-operations-and-troubleshooting.md)
- [deploy/observability/README.md](../../deploy/observability/README.md)
