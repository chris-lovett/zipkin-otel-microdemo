#!/bin/bash
# Fix Grafana Dashboard Namespace Variable
# This script updates the Consul Data Plane Performance dashboard to use Envoy metrics
# for the namespace variable instead of Kubernetes cadvisor metrics

set -e

DASHBOARD_NAME="consul-data-plane-performance"
NAMESPACE="observability"

echo "=== Fixing Grafana Dashboard Namespace Variable ==="
echo ""
echo "Dashboard: $DASHBOARD_NAME"
echo "Namespace: $NAMESPACE"
echo ""

# Backup the current dashboard
echo "1. Backing up current dashboard..."
kubectl get configmap $DASHBOARD_NAME -n $NAMESPACE -o json > /tmp/${DASHBOARD_NAME}-backup-$(date +%Y%m%d-%H%M%S).json
echo "   ✓ Backup saved to /tmp/${DASHBOARD_NAME}-backup-$(date +%Y%m%d-%H%M%S).json"
echo ""

# Update the namespace variable query
echo "2. Updating namespace variable query..."
kubectl get configmap $DASHBOARD_NAME -n $NAMESPACE -o json | \
jq '.data."consul-data-plane-performance.json" |= (fromjson | 
  .templating.list |= map(
    if .name == "namespace" then
      .definition = "label_values(envoy_cluster_upstream_rq_total, namespace)" |
      .query.query = "label_values(envoy_cluster_upstream_rq_total, namespace)" |
      .current = {"text": "tracing-demo", "value": "tracing-demo"}
    else . end
  ) | tojson)' | kubectl apply -f -
echo "   ✓ ConfigMap updated"
echo ""

# Trigger Grafana to reload the dashboard
echo "3. Triggering Grafana dashboard reload..."
kubectl annotate grafanadashboard $DASHBOARD_NAME -n $NAMESPACE resync-requested="$(date +%s)" --overwrite
echo "   ✓ Dashboard reload triggered"
echo ""

# Verify the change
echo "4. Verifying changes..."
QUERY=$(kubectl get configmap $DASHBOARD_NAME -n $NAMESPACE -o jsonpath='{.data.consul-data-plane-performance\.json}' | jq -r '.templating.list[] | select(.name=="namespace") | .query.query')
CURRENT=$(kubectl get configmap $DASHBOARD_NAME -n $NAMESPACE -o jsonpath='{.data.consul-data-plane-performance\.json}' | jq -r '.templating.list[] | select(.name=="namespace") | .current.value')

echo "   Namespace variable query: $QUERY"
echo "   Current value: $CURRENT"
echo ""

if [ "$QUERY" = "label_values(envoy_cluster_upstream_rq_total, namespace)" ]; then
    echo "✅ SUCCESS! Dashboard namespace variable updated successfully."
    echo ""
    echo "Next steps:"
    echo "1. Refresh the Grafana dashboard in your browser (Ctrl+R or Cmd+R)"
    echo "2. The namespace dropdown should now show 'tracing-demo'"
    echo "3. The service dropdown should populate with: cart, catalog, checkout, frontend, inventory, payment, zipkin"
    echo "4. Generate traffic: cd loadtest && ./simple-load.sh"
else
    echo "❌ ERROR: Dashboard update may have failed. Query is: $QUERY"
    exit 1
fi

# Made with Bob
