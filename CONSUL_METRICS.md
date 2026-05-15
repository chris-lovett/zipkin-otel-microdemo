# Consul UI Metrics

## Purpose

This document explains how Consul UI metrics fit into this demo and where to find the current implementation workflow.

For the canonical deployment and dashboard setup, use [`deploy/observability/README.md`](deploy/observability/README.md).

## Metrics Path in This Demo

The metrics flow is:

```text
Consul UI
  -> Consul server metrics proxy
  -> Prometheus
  -> Envoy / consul-dataplane metrics on port 20200
```

Grafana dashboards linked from the Consul UI are patched locally so their variables and PromQL align with the labels emitted by this environment.

## Canonical Files

Use these files together:

- [`deploy/observability/README.md`](deploy/observability/README.md) — current observability workflow
- [`deploy/observability/fix-grafana-dashboard.sh`](deploy/observability/fix-grafana-dashboard.sh) — dashboard refresh/update helper
- [`deploy/observability/patch-dashboard-consul-vars.py`](deploy/observability/patch-dashboard-consul-vars.py) — rewrites dashboard variables and PromQL for Consul deep-link use
- [`PROJECT_STATUS.md`](PROJECT_STATUS.md) — current documentation map
- [`CONSUL_TOPOLOGY.md`](CONSUL_TOPOLOGY.md) — topology behavior and dependency model

## What to Verify

### 1. Consul UI metrics is enabled

Your Consul values must enable UI metrics and point Consul at the Prometheus base URL.

### 2. Prometheus is scraping dataplane metrics

Prometheus must be able to scrape Envoy / dataplane metrics from the demo workloads.

### 3. Dashboard deep links match dashboard variables

Consul passes dashboard variables such as service and namespace. The Grafana dashboard must use matching variable names and label filters, which is why the local patching step exists.

### 4. Traffic is flowing through the mesh

Without fresh in-mesh traffic, topology and service metrics will be sparse or empty.

Use:

```bash
cd loadtest
./mesh-load.sh
```

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

## Operational Guidance

When debugging metrics for this repo, prefer this order:

1. Confirm the app pods and dataplane sidecars are healthy
2. Generate fresh mesh traffic with [`loadtest/mesh-load.sh`](loadtest/mesh-load.sh)
3. Verify Prometheus contains the expected Envoy series
4. Verify Consul UI metrics configuration
5. Verify the Grafana dashboard patch workflow under [`deploy/observability/`](deploy/observability)

## Historical Notes

Older versions of this repo included multiple alternative implementation paths and one-off fixes. Those are historical only.

If you need background on previous attempts, use [`docs/archive/README.md`](docs/archive/README.md), but do not treat archived documents as the current implementation guide.

## Short Version

If you want Consul UI metrics and linked Grafana dashboards to work in this repo:

- follow [`deploy/observability/README.md`](deploy/observability/README.md)
- use the dashboard patch scripts in [`deploy/observability/`](deploy/observability)
- generate traffic with [`loadtest/mesh-load.sh`](loadtest/mesh-load.sh)