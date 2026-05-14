#!/bin/bash
# Script to upgrade the Helm chart and restart pods to enable Consul topology graph

set -e

NAMESPACE="tracing-demo"
RELEASE_NAME="zipkin-demo"
CHART_PATH="./charts/zipkin-otel-microdemo"

echo "=========================================="
echo "Upgrading Helm Chart for Topology Support"
echo "=========================================="
echo ""

# Step 1: Upgrade the Helm release
echo "Step 1: Upgrading Helm release..."
helm upgrade $RELEASE_NAME $CHART_PATH \
  --namespace $NAMESPACE \
  --reuse-values

echo "✅ Helm upgrade complete"
echo ""

# Step 2: Restart all deployments to pick up new annotations
echo "Step 2: Restarting all deployments to apply new Consul annotations..."
kubectl rollout restart deployment -n $NAMESPACE

echo "✅ Deployments restarted"
echo ""

# Step 3: Wait for rollout to complete
echo "Step 3: Waiting for rollout to complete..."
echo ""

for deployment in frontend catalog cart checkout payment inventory zipkin; do
  echo "Waiting for $deployment..."
  kubectl rollout status deployment/$deployment -n $NAMESPACE --timeout=120s
done

echo ""
echo "✅ All deployments rolled out successfully"
echo ""

# Step 4: Verify annotations
echo "Step 4: Verifying Consul annotations on pods..."
echo ""

echo "Checking frontend pod annotations:"
kubectl get pod -n $NAMESPACE -l app.kubernetes.io/name=frontend -o jsonpath='{.items[0].metadata.annotations.consul\.hashicorp\.com/connect-service-upstreams}' 2>/dev/null || echo "No upstreams annotation found"
echo ""

echo "Checking cart pod annotations:"
kubectl get pod -n $NAMESPACE -l app.kubernetes.io/name=cart -o jsonpath='{.items[0].metadata.annotations.consul\.hashicorp\.com/connect-service-upstreams}' 2>/dev/null || echo "No upstreams annotation found"
echo ""

echo "Checking checkout pod annotations:"
kubectl get pod -n $NAMESPACE -l app.kubernetes.io/name=checkout -o jsonpath='{.items[0].metadata.annotations.consul\.hashicorp\.com/connect-service-upstreams}' 2>/dev/null || echo "No upstreams annotation found"
echo ""

# Step 5: Instructions for viewing topology
echo "=========================================="
echo "✅ Upgrade Complete!"
echo "=========================================="
echo ""
echo "To view the Consul topology graph:"
echo ""
echo "1. Port-forward to Consul UI:"
echo "   kubectl port-forward -n consul svc/consul-ui 8500:443"
echo ""
echo "2. Open in browser:"
echo "   https://localhost:8500"
echo ""
echo "3. Navigate to:"
echo "   Services → [select a service] → Topology tab"
echo ""
echo "Expected topology:"
echo "  - frontend → catalog, cart, checkout"
echo "  - cart → catalog"
echo "  - checkout → cart, inventory, payment"
echo ""
echo "For detailed verification steps, see: CONSUL_TOPOLOGY.md"
echo ""

# Made with Bob
