# Documentation Cleanup Summary (Legacy Note)

This file is retained as a historical note.

## Canonical Operational Docs

- [`README.md`](README.md)
- [`deploy/observability/README.md`](deploy/observability/README.md)
- [`PROJECT_STATUS.md`](PROJECT_STATUS.md)
- [`scripts/observability/`](scripts/observability/)

## Archive References (Intact)

Historical troubleshooting and superseded implementation paths remain in [`docs/archive/`](docs/archive/README.md), including:

- [`docs/archive/TROUBLESHOOTING_NO_METRICS.md`](docs/archive/TROUBLESHOOTING_NO_METRICS.md)
- [`docs/archive/QUICK_FIX_GUIDE.md`](docs/archive/QUICK_FIX_GUIDE.md)
- [`docs/archive/ROOT_CAUSE_ANALYSIS.md`](docs/archive/ROOT_CAUSE_ANALYSIS.md)
- [`docs/archive/METRICS_SOLUTION.md`](docs/archive/METRICS_SOLUTION.md)

## Why This Was Simplified

Detailed procedural runbook logic previously duplicated the canonical observability workflow and drifted over time. Runbook execution now lives only in [`deploy/observability/README.md`](deploy/observability/README.md) and [`scripts/observability/`](scripts/observability/).