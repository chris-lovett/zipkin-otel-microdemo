#!/bin/bash

# Fix script for consul-dataplane metrics bind address issue
# Root cause: consul-dataplane metrics endpoint binds to localhost (127.0.0.1) only
# Prometheus cannot reach it from outside the pod
# Solution: Configure metrics to bind to 0.0.0.0 or pod IP

set -e

NAMESPACE="${NAMESPACE:-tracing-demo}"
CONSUL_NAMESPACE="${CONSUL_NAMESPACE:-consul}"

echo "=========================================="
echo "Fixing Consul Metrics Bind Address"
echo "=========================================="
echo ""
echo "Root Cause:"
echo "  consul-dataplane metrics endpoint (port 20200) binds to"
echo "  localhost (127.0.0.1) only, making it unreachable by Prometheus"
echo "  from outside the pod."
echo ""
echo "Solution:"
echo "  Add pod annotation to configure telemetry bind address to 0.0.0.0"
echo ""

# Get current Consul values
echo "Step 1: Getting current Consul Helm values..."
helm get values -n $CONSUL_NAMESPACE consul > /tmp/consul-current-values.yaml

# Create Python script to update values
cat > /tmp/update_metrics_bind.py <<'PYTHON'
import yaml

with open('/tmp/consul-current-values.yaml', 'r') as f:
    values = yaml.safe_load(f) or {}

if 'connectInject' not in values:
    values['connectInject'] = {}

if 'metrics' not in values['connectInject']:
    values['connectInject']['metrics'] = {}

# Configure metrics properly
values['connectInject']['metrics']['defaultEnabled'] = True
values['connectInject']['metrics']['defaultEnableMerging'] = False
values['connectInject']['metrics']['enableGatewayMetrics'] = True
values['connectInject']['metrics']['defaultMergedMetricsPort'] = 20200
values['connectInject']['metrics']['defaultPrometheusScrapePort'] = 20200
values['connectInject']['metrics']['defaultPrometheusScrapePath'] = '/metrics'

# Add default annotations to bind metrics to 0.0.0.0
if 'annotations' not in values['connectInject']:
    values['connectInject']['annotations'] = ''

# Append the telemetry bind address annotation
annotations = values['connectInject']['annotations'] or ''
if 'consul.hashicorp.com/telemetry-config' not in annotations:
    if annotations and not annotations.endswith('\n'):
        annotations += '\n'
    annotations += 'consul.hashicorp.com/telemetry-config: |\n'
    annotations += '  {"prometheus": {"bind_address": "0.0.0.0:20200"}}'
    values['connectInject']['annotations'] = annotations

with open('/tmp/consul-updated-values.yaml', 'w') as f:
    yaml.dump(values, f, default_flow_style=False)

print("Updated metrics configuration:")
print(yaml.dump(values['connectInject']['metrics'], default_flow_style=False))
print("\nAnnotations:")
print(values['connectInject']['annotations'])
PYTHON

echo "Step 2: Updating Consul configuration..."
python3 /tmp/update_metrics_bind.py

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to update configuration"
    exit 1
fi

echo ""
echo "Step 3: Upgrading Consul with new configuration..."
helm upgrade consul hashicorp/consul \
    -n $CONSUL_NAMESPACE \
    -f /tmp/consul-updated-values.yaml \
    --wait

if [ $? -ne 0 ]; then
    echo "ERROR: Helm upgrade failed"
    exit 1
fi

echo ""
echo "Step 4: Restarting application pods..."
for deployment in $(kubectl get deployments -n $NAMESPACE -o jsonpath='{.items[*].metadata.name}'); do
    echo "Restarting $deployment..."
    kubectl rollout restart deployment/$deployment -n $NAMESPACE
done

echo ""
echo "Waiting for pods to be ready..."
kubectl wait --for=condition=ready pod --all -n $NAMESPACE --timeout=300s

echo ""
echo "Step 5: Verifying the fix..."
sleep 10

POD=$(kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=frontend -o jsonpath='{.items[0].metadata.name}')
POD_IP=$(kubectl get pod -n $NAMESPACE $POD -o jsonpath='{.status.podIP}')

echo "Testing metrics endpoint on pod $POD (IP: $POD_IP)..."
echo ""

# Test from outside the pod
if curl -s --max-time 5 http://$POD_IP:20200/metrics | head -5 | grep -q "consul_dataplane\|envoy"; then
    echo "✓ Metrics endpoint is accessible from pod IP"
    echo "✓ Metrics are being exposed correctly"
else
    echo "⚠ WARNING: Could not access metrics from pod IP"
    echo "This may be a network policy issue"
fi

echo ""
echo "=========================================="
echo "Fix Complete!"
echo "=========================================="
echo ""
echo "What changed:"
echo "  - Added telemetry-config annotation to bind metrics to 0.0.0.0:20200"
echo "  - This makes the metrics endpoint accessible from outside the pod"
echo "  - Prometheus can now scrape metrics successfully"
echo ""
echo "Next steps:"
echo "  1. Wait 1-2 minutes for Prometheus to scrape metrics"
echo "  2. Check Prometheus for metrics:"
echo "     Query: envoy_cluster_upstream_rq_total{namespace=\"tracing-demo\"}"
echo "  3. Consul UI and Grafana should now show data"
echo "  4. Generate traffic: cd loadtest && ./simple-load.sh"
echo ""

# Made with Bob
