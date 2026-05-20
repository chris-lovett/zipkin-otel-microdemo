#!/bin/bash
# Fix script to force apply the upstream annotations

set -e

NAMESPACE="tracing-demo"
RELEASE_NAME="zipkin-demo"
CHART_PATH="./charts/zipkin-otel-microdemo"

echo "=========================================="
echo "Fixing Consul Topology Annotations"
echo "=========================================="
echo ""

echo "Problem: The connect-service-upstreams annotations are missing from pods."
echo "Solution: Force a full Helm upgrade without --reuse-values"
echo ""

# Step 1: Upgrade Helm release WITHOUT --reuse-values to force template re-evaluation
echo "Step 1: Upgrading Helm release (forcing template re-evaluation)..."
helm upgrade $RELEASE_NAME $CHART_PATH \
  --namespace $NAMESPACE \
  --set global.imageRegistry=quay.io/chris_lovett/zipkin-otel-microdemo \
  --set global.imagePullSecrets[0].name=quay-pull

echo "✅ Helm upgrade complete"
echo ""

# Step 2: Delete all pods to force recreation with new annotations
echo "Step 2: Deleting all pods to force recreation with new annotations..."
kubectl delete pods --all -n $NAMESPACE

echo "✅ Pods deleted, waiting for recreation..."
echo ""

# Step 3: Wait for all deployments to be ready
echo "Step 3: Waiting for all deployments to be ready..."
sleep 10

for deployment in frontend catalog cart checkout payment inventory zipkin; do
  echo "Waiting for $deployment..."
  kubectl rollout status deployment/$deployment -n $NAMESPACE --timeout=180s
done

echo ""
echo "✅ All deployments are ready"
echo ""

# Step 4: Verify the annotations are now present
echo "Step 4: Verifying connect-service-upstreams annotations..."
echo ""

echo "Frontend upstreams:"
FRONTEND_UPSTREAMS=$(kubectl get pod -n $NAMESPACE -l app.kubernetes.io/name=frontend -o jsonpath='{.items[0].metadata.annotations.consul\.hashicorp\.com/connect-service-upstreams}' 2>/dev/null || echo "")
if [ -z "$FRONTEND_UPSTREAMS" ]; then
  echo "❌ STILL MISSING!"
else
  echo "✅ $FRONTEND_UPSTREAMS"
fi
echo ""

echo "Cart upstreams:"
CART_UPSTREAMS=$(kubectl get pod -n $NAMESPACE -l app.kubernetes.io/name=cart -o jsonpath='{.items[0].metadata.annotations.consul\.hashicorp\.com/connect-service-upstreams}' 2>/dev/null || echo "")
if [ -z "$CART_UPSTREAMS" ]; then
  echo "❌ STILL MISSING!"
else
  echo "✅ $CART_UPSTREAMS"
fi
echo ""

echo "Checkout upstreams:"
CHECKOUT_UPSTREAMS=$(kubectl get pod -n $NAMESPACE -l app.kubernetes.io/name=checkout -o jsonpath='{.items[0].metadata.annotations.consul\.hashicorp\.com/connect-service-upstreams}' 2>/dev/null || echo "")
if [ -z "$CHECKOUT_UPSTREAMS" ]; then
  echo "❌ STILL MISSING!"
else
  echo "✅ $CHECKOUT_UPSTREAMS"
fi
echo ""

# Step 5: Final status
echo "=========================================="
if [ -n "$FRONTEND_UPSTREAMS" ] && [ -n "$CART_UPSTREAMS" ] && [ -n "$CHECKOUT_UPSTREAMS" ]; then
  echo "✅ SUCCESS! Annotations Applied"
  echo "=========================================="
  echo ""
  echo "The topology graph should now populate in Consul UI."
  echo ""
  echo "To view:"
  echo "1. kubectl port-forward -n consul svc/consul-ui 8500:443"
  echo "2. Open https://localhost:8500"
  echo "3. Go to Services → [service] → Topology tab"
  echo ""
  echo "Wait 1-2 minutes for Consul to sync, then check the topology view."
else
  echo "❌ PROBLEM: Annotations Still Missing"
  echo "=========================================="
  echo ""
  echo "The annotations are still not present. This suggests:"
  echo "1. The Helm chart templates may not be correct"
  echo "2. There may be a Consul webhook issue"
  echo ""
  echo "Next steps:"
  echo "1. Verify the chart template has the annotations:"
  echo "   cat charts/zipkin-otel-microdemo/templates/services.yaml | grep -A3 annotations"
  echo ""
  echo "2. Check if consulUpstreams is set in values.yaml:"
  echo "   cat charts/zipkin-otel-microdemo/values.yaml | grep consulUpstreams"
  echo ""
  echo "3. Check Consul webhook logs:"
  echo "   kubectl logs -n consul -l component=connect-injector --tail=50"
fi
echo ""

# Made with Bob
