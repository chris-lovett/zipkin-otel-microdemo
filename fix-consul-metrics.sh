#!/bin/bash
# Fix script to enable Consul UI metrics

set -e

CONSUL_NAMESPACE="consul"
PROMETHEUS_NAMESPACE="observability"
PROMETHEUS_URL="http://prometheus-server.observability.svc.cluster.local"

echo "=========================================="
echo "Fixing Consul UI Metrics Configuration"
echo "=========================================="
echo ""

echo "Detected configuration:"
echo "  Consul namespace: $CONSUL_NAMESPACE"
echo "  Prometheus namespace: $PROMETHEUS_NAMESPACE"
echo "  Prometheus URL: $PROMETHEUS_URL"
echo ""

# Step 1: Verify Prometheus is accessible
echo "Step 1: Verifying Prometheus is accessible..."
echo ""

PROM_SVC=$(kubectl get svc -n $PROMETHEUS_NAMESPACE prometheus-server -o name 2>/dev/null || echo "")
if [ -z "$PROM_SVC" ]; then
  echo "❌ Prometheus service not found in namespace: $PROMETHEUS_NAMESPACE"
  echo ""
  echo "Please verify:"
  echo "1. Prometheus is deployed"
  echo "2. The service name is 'prometheus-server'"
  echo "3. The namespace is correct"
  echo ""
  exit 1
else
  echo "✅ Prometheus service found: $PROM_SVC"
fi
echo ""

# Step 2: Test connectivity from Consul to Prometheus
echo "Step 2: Testing connectivity from Consul to Prometheus..."
echo ""

CONSUL_POD=$(kubectl get pod -n $CONSUL_NAMESPACE -l component=server -o jsonpath='{.items[0].metadata.name}')
echo "Testing from Consul pod: $CONSUL_POD"
echo ""

# Test if Consul can reach Prometheus
kubectl exec -it $CONSUL_POD -n $CONSUL_NAMESPACE -- \
  sh -c "wget -qO- --timeout=5 ${PROMETHEUS_URL}/api/v1/query?query=up 2>&1" | head -5 || \
  echo "⚠️  Warning: Could not reach Prometheus from Consul pod"
echo ""

# Step 3: Verify Helm values are correct
echo "Step 3: Verifying Consul Helm values..."
echo ""

helm get values consul -n $CONSUL_NAMESPACE | grep -A5 "metrics:" || echo "No metrics config found"
echo ""

# Step 4: Restart Consul servers to pick up configuration
echo "Step 4: Restarting Consul server pods to apply metrics configuration..."
echo ""

echo "This will restart Consul servers one at a time (rolling restart)..."
read -p "Continue? (y/n) " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Aborted."
  exit 1
fi

# Rolling restart of Consul servers
kubectl rollout restart statefulset/consul-server -n $CONSUL_NAMESPACE

echo "Waiting for Consul servers to be ready..."
kubectl rollout status statefulset/consul-server -n $CONSUL_NAMESPACE --timeout=300s

echo ""
echo "✅ Consul servers restarted"
echo ""

# Step 5: Verify ui_config is now present
echo "Step 5: Verifying ui_config is now in server configuration..."
echo ""

sleep 10  # Give Consul a moment to fully start

kubectl exec -it consul-server-0 -n $CONSUL_NAMESPACE -- \
  cat /consul/config/server.json 2>/dev/null | grep -A10 "ui_config" || \
  echo "⚠️  ui_config still not found - may need manual configuration"
echo ""

# Step 6: Test Prometheus query from Consul
echo "Step 6: Testing Prometheus query from Consul server..."
echo ""

kubectl exec -it consul-server-0 -n $CONSUL_NAMESPACE -- \
  sh -c "wget -qO- '${PROMETHEUS_URL}/api/v1/query?query=envoy_cluster_upstream_rq_total' 2>&1" | head -10 || \
  echo "⚠️  Could not query Prometheus for Envoy metrics"
echo ""

# Step 7: Check if Prometheus is scraping Envoy metrics
echo "Step 7: Checking if Prometheus has Envoy metrics..."
echo ""

# Port-forward to Prometheus and query
echo "To verify Prometheus has Envoy metrics, run:"
echo ""
echo "  kubectl port-forward -n $PROMETHEUS_NAMESPACE svc/prometheus-server 9090:80"
echo "  curl 'http://localhost:9090/api/v1/query?query=envoy_cluster_upstream_rq_total'"
echo ""

echo "=========================================="
echo "Next Steps"
echo "=========================================="
echo ""
echo "1. Access Consul UI:"
echo "   kubectl port-forward -n consul svc/consul-ui 8500:443"
echo "   Open: https://localhost:8500"
echo ""
echo "2. Navigate to Services → [service name] → Metrics"
echo ""
echo "3. If metrics still don't appear:"
echo "   a. Verify Prometheus is scraping Envoy sidecars"
echo "   b. Check Prometheus targets: http://localhost:9090/targets"
echo "   c. Generate traffic: cd loadtest && ./simple-load.sh"
echo "   d. Check for NetworkPolicies blocking traffic"
echo ""
echo "4. For detailed troubleshooting, see: CONSUL_METRICS.md"
echo ""

# Made with Bob
