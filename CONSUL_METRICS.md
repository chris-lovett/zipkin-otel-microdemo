# Consul UI Metrics

## Purpose

This document defines the Consul UI metrics model used in this repository and the verification criteria for a healthy setup.

For deployment and operational runbooks, use [`README.md`](README.md) and [`deploy/observability/README.md`](deploy/observability/README.md).

## Metrics Path in This Demo

The metrics flow is:

```text
Consul UI
  -> Consul server metrics proxy
  -> Prometheus
  -> Envoy / consul-dataplane metrics on port 20200
```

Grafana dashboards linked from the Consul UI are patched locally so their variables and PromQL align with the labels emitted by this environment.

## Canonical Sources

Use these files together:

- [`README.md`](README.md) — operator entrypoint and runbook commands
- [`deploy/observability/README.md`](deploy/observability/README.md) — canonical observability workflow
- [`deploy/observability/fix-grafana-dashboard.sh`](deploy/observability/fix-grafana-dashboard.sh) — dashboard refresh/update helper
- [`deploy/observability/patch-dashboard-consul-vars.py`](deploy/observability/patch-dashboard-consul-vars.py) — rewrites dashboard variables and PromQL for Consul deep-link use
- [`PROJECT_STATUS.md`](PROJECT_STATUS.md) — current documentation map
- [`CONSUL_TOPOLOGY.md`](CONSUL_TOPOLOGY.md) — topology behavior and dependency model

## Verification Criteria

Use this section as pass/fail criteria. It intentionally avoids deployment procedure details.

### 1. Consul UI metrics provider is configured

Expected state:
- provider is `prometheus`
- base URL resolves to the in-cluster Prometheus service used by Consul

### 2. Prometheus scrape coverage includes dataplane metrics

Expected state:
- Consul dataplane/Envoy targets are up
- namespace and label selectors match deployed workloads
- series for Envoy traffic/latency are present

### 3. Dashboard deep-link variables are label-compatible

Expected state:
- Consul template variables map to active dashboard variable names
- PromQL label filters match this environment's metric schema
- deep links open scoped panels for service/namespace without manual edits

### 4. Topology metrics reflect live in-mesh traffic

Expected state:
- topology edges show non-zero request/traffic values during load
- stale windows can return to zero after traffic stops (normal)

## Common Failure Modes

### Empty metrics in Consul UI

Usually one of:

- no recent mesh traffic
- Prometheus scrape path is broken
- Consul cannot reach the configured Prometheus base URL
- the relevant Envoy series are present but dashboard or UI queries do not match the active labels

### Empty Grafana panels from Consul deep links

Usually one of:

- dashboard variable mismatch, especially service vs app naming
- namespace filters using stale labels
- panel PromQL built for a different metric label schema
- resource panels joining against kube-state-metrics labels that do not match the current cluster data

## Verification Outcome Matrix

- **Healthy:** topology metrics stream, Prometheus targets are up, and deep links open correctly scoped dashboards.
- **Partially healthy:** Prometheus targets are up but topology/deep links are empty due to variable or label mismatch.
- **Unhealthy:** missing scrape data, unreachable Prometheus base URL, or no in-mesh traffic in active windows.

## Historical Notes

Older versions of this repo included multiple alternative implementation paths and one-off fixes. Those are historical only.

If you need background on previous attempts, use [`docs/archive/README.md`](docs/archive/README.md), but do not treat archived documents as the current implementation guide.