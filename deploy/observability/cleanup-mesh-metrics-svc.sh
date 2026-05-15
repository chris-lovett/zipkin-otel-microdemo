#!/usr/bin/env bash
# Remove leftover headless Service from the old ServiceMonitor / sidecar pattern.
set -euo pipefail
kubectl delete svc consul-mesh-metrics -n "${NAMESPACE:-tracing-demo}" --ignore-not-found
echo "Deleted consul-mesh-metrics Service (removes bogus topology upstream after catalog sync)."
