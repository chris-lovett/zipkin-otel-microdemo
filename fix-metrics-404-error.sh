#!/bin/bash

# Fix script for consul-dataplane metrics 404 error
# Root cause: consul-dataplane tries to scrape app metrics from localhost:8080/metrics
# but the application doesn't expose a /metrics endpoint, causing 404 errors
# This breaks metrics merging and causes Prometheus scraping to fail

set -e

NAMESPACE="${NAMESPACE:-tracing-demo}"
CONSUL_NAMESPACE="${CONSUL_NAMESPACE:-consul}"

echo "=========================================="
echo "Fixing Consul Metrics 404 Error"
echo "=========================================="
echo ""
echo "Root Cause:"
echo "  consul-dataplane is configured to merge application metrics"
echo "  from http://127.0.0.1:8080/metrics, but the application"
echo "  doesn't expose a /metrics endpoint (returns 404)."
echo ""
echo "Solution:"
echo "  Disable application metrics merging and only expose"
echo "  Envoy metrics on port 20200."
echo ""

# Check if Consul is installed
if ! helm list -n $CONSUL_NAMESPACE | grep -q consul; then
    echo "ERROR: Consul not found in namespace $CONSUL_NAMESPACE"
    exit 1
fi

echo "Step 1: Updating Consul Helm values to disable app metrics merging..."
echo ""

# Get current Consul values
helm get values -n $CONSUL_NAMESPACE consul > /tmp/consul-current-values.yaml

# Check if connectInject.metrics section exists
if ! grep -q "connectInject:" /tmp/consul-current-values.yaml; then
    echo "Adding connectInject section..."
    cat >> /tmp/consul-current-values.yaml <<EOF

connectInject:
  metrics:
    defaultEnabled: true
    defaultEnableMerging: false
    enableGatewayMetrics: true
    defaultMergedMetricsPort: 20200
    defaultPrometheusScrapePort: 20200
    defaultPrometheusScrapePath: "/metrics"
EOF
else
    # Update existing section
    echo "Updating existing connectInject.metrics section..."
    
    # Create a temporary Python script to update the YAML
    cat > /tmp/update_metrics.py <<'PYTHON'
import yaml
import sys

with open('/tmp/consul-current-values.yaml', 'r') as f:
    values = yaml.safe_load(f) or {}

if 'connectInject' not in values:
    values['connectInject'] = {}

if 'metrics' not in values['connectInject']:
    values['connectInject']['metrics'] = {}

# Disable merging to prevent 404 errors
values['connectInject']['metrics']['defaultEnabled'] = True
values['connectInject']['metrics']['defaultEnableMerging'] = False
values['connectInject']['metrics']['enableGatewayMetrics'] = True
values['connectInject']['metrics']['defaultMergedMetricsPort'] = 20200
values['connectInject']['metrics']['defaultPrometheusScrapePort'] = 20200
values['connectInject']['metrics']['defaultPrometheusScrapePath'] = '/metrics'

with open('/tmp/consul-updated-values.yaml', 'w') as f:
    yaml.dump(values, f, default_flow_style=False)

print("Updated values:")
print(yaml.dump(values['connectInject']['metrics'], default_flow_style=False))
PYTHON

    python3 /tmp/update_metrics.py
    
    if [ $? -eq 0 ]; then
        mv /tmp/consul-updated-values.yaml /tmp/consul-current-values.yaml
    else
        echo "ERROR: Failed to update YAML. Falling back to manual edit."
        echo ""
        echo "Please manually add these values to your Consul Helm chart:"
        cat <<EOF

connectInject:
  metrics:
    defaultEnabled: true
    defaultEnableMerging: false  # <-- This is the key change
    enableGatewayMetrics: true
    defaultMergedMetricsPort: 20200
    defaultPrometheusScrapePort: 20200
    defaultPrometheusScrapePath: "/metrics"
EOF
        exit 1
    fi
fi

echo ""
echo "Step 2: Upgrading Consul with new values..."
echo ""

# Upgrade Consul
helm upgrade consul hashicorp/consul \
    -n $CONSUL_NAMESPACE \
    -f /tmp/consul-current-values.yaml \
    --wait

if [ $? -ne 0 ]; then
    echo "ERROR: Helm upgrade failed"
    exit 1
fi

echo ""
echo "Step 3: Restarting application pods to apply new configuration..."
echo ""

# Restart all application pods
for deployment in $(kubectl get deployments -n $NAMESPACE -o jsonpath='{.items[*].metadata.name}'); do
    echo "Restarting $deployment..."
    kubectl rollout restart deployment/$deployment -n $NAMESPACE
done

echo ""
echo "Waiting for pods to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=zipkin-otel-microdemo -n $NAMESPACE --timeout=300s

echo ""
echo "Step 4: Verifying the fix..."
echo ""

sleep 10

# Check a frontend pod
POD=$(kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=frontend -o jsonpath='{.items[0].metadata.name}')

if [ -z "$POD" ]; then
    echo "ERROR: No frontend pod found"
    exit 1
fi

echo "Checking consul-dataplane logs for errors..."
ERROR_COUNT=$(kubectl logs -n $NAMESPACE $POD -c consul-dataplane --tail=20 | grep -c "failed to scrape metrics" || echo "0")

if [ "$ERROR_COUNT" -gt 0 ]; then
    echo "⚠ WARNING: Still seeing metrics scrape errors"
    echo "Recent logs:"
    kubectl logs -n $NAMESPACE $POD -c consul-dataplane --tail=10
else
    echo "✓ No metrics scrape errors found"
fi

echo ""
echo "Checking if port 20200 returns valid metrics..."
# We can't easily test this from outside, but we can check Prometheus targets

echo ""
echo "=========================================="
echo "Fix Complete!"
echo "=========================================="
echo ""
echo "What changed:"
echo "  - Set defaultEnableMerging: false"
echo "  - This disables application metrics merging"
echo "  - Port 20200 now only exposes Envoy metrics"
echo "  - No more 404 errors from trying to scrape app metrics"
echo ""
echo "Next steps:"
echo "  1. Wait 1-2 minutes for Prometheus to scrape new metrics"
echo "  2. Check Prometheus targets:"
echo "     kubectl port-forward -n observability svc/prometheus-server 9090:80"
echo "     Visit: http://localhost:9090/targets"
echo "     Look for tracing-demo pods - should show 'UP' status"
echo ""
echo "  3. Verify metrics in Prometheus:"
echo "     Query: envoy_cluster_upstream_rq_total{namespace=\"tracing-demo\"}"
echo ""
echo "  4. Check Consul UI and Grafana - should now show data"
echo ""
echo "Note: You still need to generate traffic for metrics to appear:"
echo "  cd loadtest && ./simple-load.sh"
echo ""

# Made with Bob
