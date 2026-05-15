#!/usr/bin/env bash
# Remove OpenShift user-workload ServiceMonitor / sidecar ConfigMap after switching to standalone Prometheus.
set -euo pipefail

NAMESPACE="${NAMESPACE:-tracing-demo}"

kubectl delete servicemonitor consul-mesh-metrics -n "$NAMESPACE" --ignore-not-found
kubectl delete configmap prometheus-sidecar-config -n "$NAMESPACE" --ignore-not-found
kubectl label namespace "$NAMESPACE" openshift.io/user-monitoring- 2>/dev/null || true

echo "Done. Redeploy the app chart to drop prometheus-sidecar containers:"
echo "  helm upgrade --install zipkin-demo ./charts/zipkin-otel-microdemo -n $NAMESPACE"
