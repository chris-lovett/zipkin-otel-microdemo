#!/bin/bash
# Diagnostic script to troubleshoot Consul UI metrics issues

set -u

CONSUL_NAMESPACE="consul"
PROMETHEUS_NAMESPACE="observability"

find_prometheus() {
  local ns
  for ns in "$PROMETHEUS_NAMESPACE" observability monitoring prometheus-system default consul; do
    local pod
    pod=$(kubectl get pods -n "$ns" -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ -n "$pod" ]; then
      PROMETHEUS_NAMESPACE="$ns"
      echo "$pod"
      return 0
    fi

    pod=$(kubectl get pods -n "$ns" -l app=prometheus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ -n "$pod" ]; then
      PROMETHEUS_NAMESPACE="$ns"
      echo "$pod"
      return 0
    fi
  done

  return 1
}

pod_http_get() {
  local namespace="$1"
  local pod="$2"
  local container="$3"
  local url="$4"
  kubectl exec -n "$namespace" "$pod" -c "$container" -- sh -c "if command -v wget >/dev/null 2>&1; then wget -qO- '$url'; elif command -v curl >/dev/null 2>&1; then curl -sf '$url'; else exit 127; fi" 2>/dev/null
}

echo "=========================================="
echo "Consul UI Metrics Diagnostics"
echo "=========================================="
echo ""

# Check 1: Verify Consul UI configuration
echo "1. Checking Consul UI configuration..."
echo ""
CONSUL_POD=$(kubectl get pod -n $CONSUL_NAMESPACE -l component=server -o jsonpath='{.items[0].metadata.name}')
echo "Consul server pod: $CONSUL_POD"
echo ""

echo "Checking for ui_config in Consul server..."
kubectl exec $CONSUL_POD -n $CONSUL_NAMESPACE -- cat /consul/config/server.json 2>/dev/null | grep -A10 "ui_config" || echo "No ui_config found in server.json (this can be expected when ui.metrics is configured through Helm values)"
echo ""

# Check 2: Verify Prometheus is running
echo "2. Checking if Prometheus is running..."
echo ""
PROM_POD=$(find_prometheus)
if [ -z "$PROM_POD" ]; then
  echo "❌ No Prometheus pods found via common labels"
else
  echo "✅ Prometheus found in namespace: $PROMETHEUS_NAMESPACE"
  kubectl get pod -n $PROMETHEUS_NAMESPACE "$PROM_POD"
fi
echo ""

# Check 3: Verify Prometheus service
echo "3. Checking Prometheus service..."
echo ""
PROM_SVC=$(kubectl get svc -n $PROMETHEUS_NAMESPACE -l app.kubernetes.io/name=prometheus -o name 2>/dev/null || echo "")
if [ -z "$PROM_SVC" ]; then
  PROM_SVC=$(kubectl get svc -n $PROMETHEUS_NAMESPACE -l app=prometheus -o name 2>/dev/null || echo "")
fi
if [ -z "$PROM_SVC" ]; then
  echo "❌ No Prometheus service found"
else
  echo "✅ Prometheus service found:"
  kubectl get svc -n $PROMETHEUS_NAMESPACE | grep -E "prometheus|NAME"
fi
echo ""

# Check 4: Check Consul Helm values for metrics configuration
echo "4. Checking Consul Helm values for metrics configuration..."
echo ""
helm get values consul -n $CONSUL_NAMESPACE 2>/dev/null | grep -A20 "ui:" || echo "Could not retrieve Consul Helm values"
echo ""

# Check 5: Check if Envoy sidecars are exposing metrics
echo "5. Checking if Envoy sidecars expose metrics on port 20200..."
echo ""
FRONTEND_POD=$(kubectl get pod -n tracing-demo -l app.kubernetes.io/name=frontend -o jsonpath='{.items[0].metadata.name}')
echo "Testing metrics endpoint on frontend pod: $FRONTEND_POD"
if pod_http_get tracing-demo "$FRONTEND_POD" consul-dataplane http://localhost:20200/metrics | head -20; then
  true
else
  echo "❌ Could not retrieve metrics from dataplane sidecar on /metrics"
fi
echo ""

# Check 6: Check for prometheus.io annotations on pods
echo "6. Checking for Prometheus scrape annotations on pods..."
echo ""
echo "Frontend pod annotations:"
kubectl get pod -n tracing-demo -l app.kubernetes.io/name=frontend -o jsonpath='{.items[0].metadata.annotations}' | jq 'with_entries(select(.key | startswith("prometheus.io")))'
echo ""

# Check 7: Check if Prometheus is scraping Consul services
echo "7. Checking Prometheus targets (if accessible)..."
echo ""
if [ -n "$PROM_POD" ]; then
  echo "Prometheus pod: $PROM_POD"
  echo "Checking Prometheus configuration..."
  kubectl exec $PROM_POD -n $PROMETHEUS_NAMESPACE -- cat /etc/prometheus/prometheus.yml 2>/dev/null | grep -A10 "consul" || echo "No Consul scrape config found"
else
  echo "❌ Could not find Prometheus pod to check configuration"
fi
echo ""

# Check 8: Verify ServiceMonitor CRDs (if using Prometheus Operator)
echo "8. Checking for ServiceMonitor CRDs..."
echo ""
kubectl get servicemonitor -n $CONSUL_NAMESPACE 2>/dev/null || echo "No ServiceMonitors found (can be expected on standalone Prometheus path)"
echo ""

echo "=========================================="
echo "Diagnostic Summary"
echo "=========================================="
echo ""
echo "Common issues and solutions:"
echo ""
echo "1. Consul UI not configured for metrics:"
echo "   - Add ui_config.metrics_provider to Consul Helm values"
echo "   - Add ui_config.metrics_proxy settings"
echo ""
echo "2. Prometheus not found or not scraping:"
echo "   - Verify Prometheus is deployed and running"
echo "   - Check Prometheus scrape configuration includes Consul services"
echo "   - Verify ServiceMonitor or scrape configs exist"
echo ""
echo "3. Envoy metrics not exposed:"
echo "   - Verify prometheus.io annotations on pods"
echo "   - Check Envoy admin interface on port 20200"
echo ""
echo "4. Network connectivity issues:"
echo "   - Verify Consul can reach Prometheus service"
echo "   - Check NetworkPolicies aren't blocking traffic"
echo ""
echo "For detailed configuration steps, see: CONSUL_METRICS.md"
echo ""

exit 0

# Made with Bob
