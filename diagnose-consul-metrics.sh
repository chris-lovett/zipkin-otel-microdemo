#!/bin/bash
# Diagnostic script to troubleshoot Consul UI metrics issues

set -e

CONSUL_NAMESPACE="consul"
PROMETHEUS_NAMESPACE="consul"  # Adjust if Prometheus is in a different namespace

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
kubectl exec -it $CONSUL_POD -n $CONSUL_NAMESPACE -- cat /consul/config/server.json 2>/dev/null | grep -A10 "ui_config" || echo "No ui_config found in server.json"
echo ""

# Check 2: Verify Prometheus is running
echo "2. Checking if Prometheus is running..."
echo ""
PROM_PODS=$(kubectl get pods -n $PROMETHEUS_NAMESPACE -l app=prometheus -o name 2>/dev/null || echo "")
if [ -z "$PROM_PODS" ]; then
  echo "❌ No Prometheus pods found in namespace: $PROMETHEUS_NAMESPACE"
  echo ""
  echo "Checking other common namespaces..."
  for ns in monitoring prometheus-system default; do
    PROM_CHECK=$(kubectl get pods -n $ns -l app=prometheus -o name 2>/dev/null || echo "")
    if [ -n "$PROM_CHECK" ]; then
      echo "✅ Found Prometheus in namespace: $ns"
      PROMETHEUS_NAMESPACE=$ns
      break
    fi
  done
else
  echo "✅ Prometheus found in namespace: $PROMETHEUS_NAMESPACE"
  kubectl get pods -n $PROMETHEUS_NAMESPACE -l app=prometheus
fi
echo ""

# Check 3: Verify Prometheus service
echo "3. Checking Prometheus service..."
echo ""
PROM_SVC=$(kubectl get svc -n $PROMETHEUS_NAMESPACE -l app=prometheus -o name 2>/dev/null || echo "")
if [ -z "$PROM_SVC" ]; then
  echo "❌ No Prometheus service found"
else
  echo "✅ Prometheus service found:"
  kubectl get svc -n $PROMETHEUS_NAMESPACE -l app=prometheus
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
kubectl exec -it $FRONTEND_POD -n tracing-demo -c consul-dataplane -- wget -qO- http://localhost:20200/metrics 2>/dev/null | head -20 || echo "❌ Could not retrieve metrics from Envoy sidecar"
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
PROM_POD=$(kubectl get pod -n $PROMETHEUS_NAMESPACE -l app=prometheus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$PROM_POD" ]; then
  echo "Prometheus pod: $PROM_POD"
  echo "Checking Prometheus configuration..."
  kubectl exec -it $PROM_POD -n $PROMETHEUS_NAMESPACE -- cat /etc/prometheus/prometheus.yml 2>/dev/null | grep -A10 "consul" || echo "No Consul scrape config found"
else
  echo "❌ Could not find Prometheus pod to check configuration"
fi
echo ""

# Check 8: Verify ServiceMonitor CRDs (if using Prometheus Operator)
echo "8. Checking for ServiceMonitor CRDs..."
echo ""
kubectl get servicemonitor -n $CONSUL_NAMESPACE 2>/dev/null || echo "No ServiceMonitors found (may not be using Prometheus Operator)"
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

# Made with Bob
