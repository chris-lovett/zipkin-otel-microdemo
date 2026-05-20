# Operations and Troubleshooting

This section is the operations runbook entrypoint.

## Daily Operator Commands

Primary command set:
- make observability-verify
- make observability-troubleshoot
- make observability-sync-dashboards

## Canonical Troubleshooting Scripts

All active scripts are in:
- [../../scripts/observability](../../scripts/observability)

Suggested order:
1. check-consul-metrics.sh
2. diagnose-consul-metrics.sh
3. diagnose-envoy-metrics.sh
4. diagnose-topology.sh
5. troubleshoot-no-metrics.sh

## Typical Incident Patterns

1. Topology shows zero traffic:
- no recent mesh load
- wrong namespace selectors for scraping
- missing service defaults protocol entries

2. Grafana deep links open but panels are empty:
- dashboard variable mismatch
- stale datasource UID
- label schema drift in PromQL

3. Consul server metrics missing:
- ACL token not available to Prometheus scrape job
- TLS scrape mismatch or endpoint auth issue

## Escalation Path

If the canonical runbook does not resolve the issue:
- review [../../docs/archive/README.md](../../docs/archive/README.md) for historical patterns
- compare live cluster state to [../../deploy/observability/README.md](../../deploy/observability/README.md)

## Stability Rules

- keep one canonical metrics collection path active at a time
- do not introduce sidecar scrape patterns as active runbook behavior
- keep dashboard source-of-truth in repository-managed JSON and sync scripts
