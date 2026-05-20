# Consul Server Metrics - Legacy Summary

This document is retained as a legacy reference and is no longer the operational runbook.

## Canonical Path

Use these files for current production operations:

- [`deploy/observability/README.md`](deploy/observability/README.md) - canonical OpenShift-first observability workflow
- [`deploy/observability/prometheus-values.yaml`](deploy/observability/prometheus-values.yaml) - active standalone Prometheus scrape configuration
- [`scripts/observability/check-consul-metrics.sh`](scripts/observability/check-consul-metrics.sh) - server metrics verification helper
- [`scripts/observability/troubleshoot-no-metrics.sh`](scripts/observability/troubleshoot-no-metrics.sh) - canonical troubleshooting script

## Why This File Was Reduced

Earlier versions of this file contained a full procedural runbook that duplicated and sometimes diverged from the canonical observability guide. To avoid conflicting guidance, procedural content now lives only in [`deploy/observability/README.md`](deploy/observability/README.md) and [`scripts/observability/`](scripts/observability/).

## Historical Background

For detailed historical context and superseded troubleshooting paths, see:

- [`docs/archive/README.md`](docs/archive/README.md)
- [`docs/archive/TROUBLESHOOTING_NO_METRICS.md`](docs/archive/TROUBLESHOOTING_NO_METRICS.md)
- [`docs/archive/ROOT_CAUSE_ANALYSIS.md`](docs/archive/ROOT_CAUSE_ANALYSIS.md)
