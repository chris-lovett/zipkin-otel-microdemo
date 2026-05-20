#!/bin/bash

# Fix Consul Metrics Merging Configuration
# Adds missing Helm values to enable proper metrics merging on port 20200

set -e

echo "=========================================="
echo "Fixing Consul Metrics Merging"
echo "=========================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Step 1: Create Helm values patch with complete metrics configuration
echo "Step 1: Creating Helm values patch with metrics merging configuration..."

cat > /tmp/consul-metrics-merging-patch.yaml <<EOF
connectInject:
  enabled: true
  default: true
  transparentProxy:
    defaultEnabled: true
  metrics:
    defaultEnabled: true
    defaultEnableMerging: true
    enableGatewayMetrics: true
    # These are the MISSING settings that enable metrics merging
    defaultMergedMetricsPort: 20200
    defaultPrometheusScrapePort: 20200
    defaultPrometheusScrapePath: "/metrics"
EOF

echo -e "${GREEN}✓${NC} Created Helm values patch"
echo ""
echo "Patch contents:"
cat /tmp/consul-metrics-merging-patch.yaml
echo ""

# Step 2: Apply Helm upgrade
echo "Step 2: Applying Helm upgrade with metrics merging configuration..."
echo -e "${YELLOW}This will update the Consul Helm release...${NC}"

CONSUL_RELEASE=$(helm list -n consul -o json | jq -r '.[0].name')

if [ -z "$CONSUL_RELEASE" ] || [ "$CONSUL_RELEASE" == "null" ]; then
    echo -e "${RED}✗${NC} Could not find Consul Helm release in consul namespace"
    exit 1
fi

helm upgrade "$CONSUL_RELEASE" hashicorp/consul \
    --namespace consul \
    --reuse-values \
    --values /tmp/consul-metrics-merging-patch.yaml

echo -e "${GREEN}✓${NC} Helm upgrade completed"

# Step 3: Restart application pods to get new consul-dataplane configuration
echo ""
echo "Step 3: Restarting application pods to apply new configuration..."
echo -e "${YELLOW}This will restart all pods in tracing-demo namespace...${NC}"

kubectl rollout restart deployment -n tracing-demo

echo -e "${GREEN}✓${NC} Rollout restart initiated"

# Step 4: Wait for pods to be ready
echo ""
echo "Step 4: Waiting for pods to be ready..."

kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=zipkin-demo -n tracing-demo --timeout=300s

echo -e "${GREEN}✓${NC} All pods are ready"

# Step 5: Verify consul-dataplane has merge port configured
echo ""
echo "Step 5: Verifying consul-dataplane configuration..."

POD_NAME=$(kubectl get pods -n tracing-demo -l app.kubernetes.io/name=frontend -o jsonpath='{.items[0].metadata.name}')

echo "Checking consul-dataplane arguments in pod: $POD_NAME"
MERGE_PORT=$(kubectl get pod -n tracing-demo $POD_NAME -o jsonpath='{.spec.containers[?(@.name=="consul-dataplane")].args}' | grep -o "telemetry-prom-merge-port=[0-9]*" || echo "NOT FOUND")

if [ "$MERGE_PORT" != "NOT FOUND" ]; then
    echo -e "${GREEN}✓${NC} Metrics merge port configured: $MERGE_PORT"
else
    echo -e "${YELLOW}⚠${NC}  Metrics merge port not found in arguments"
    echo "Full consul-dataplane args:"
    kubectl get pod -n tracing-demo $POD_NAME -o jsonpath='{.spec.containers[?(@.name=="consul-dataplane")].args}' | tr ',' '\n' | grep telemetry
fi

# Step 6: Test metrics endpoint
echo ""
echo "Step 6: Testing metrics endpoint on port 20200..."

sleep 5  # Give metrics a moment to start collecting

METRICS_TEST=$(kubectl exec -n tracing-demo $POD_NAME -c consul-dataplane -- wget -q -O- --timeout=5 http://localhost:20200/metrics 2>/dev/null | head -10)

if [ -n "$METRICS_TEST" ]; then
    echo -e "${GREEN}✓${NC} Metrics are being exposed on port 20200!"
    echo "Sample metrics:"
    echo "$METRICS_TEST"
    
    # Count Envoy metrics
    ENVOY_COUNT=$(kubectl exec -n tracing-demo $POD_NAME -c consul-dataplane -- wget -q -O- --timeout=5 http://localhost:20200/metrics 2>/dev/null | grep -c "envoy_" || echo "0")
    echo ""
    echo "Total Envoy metrics found: $ENVOY_COUNT"
else
    echo -e "${RED}✗${NC} No metrics found on port 20200"
    echo "Troubleshooting steps:"
    echo "1. Check consul-dataplane logs:"
    echo "   kubectl logs -n tracing-demo $POD_NAME -c consul-dataplane | grep -i metric"
    echo "2. Verify Consul Helm values were applied:"
    echo "   helm get values consul -n consul | grep -A 10 metrics"
fi

# Step 7: Verify Prometheus can scrape
echo ""
echo "Step 7: Verifying Prometheus scrape configuration..."

POD_IP=$(kubectl get pod -n tracing-demo $POD_NAME -o jsonpath='{.status.podIP}')
echo "Pod IP: $POD_IP"

PROM_POD=$(kubectl get pods -n observability -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[0].metadata.name}')
if [ -n "$PROM_POD" ]; then
    echo "Testing scrape from Prometheus pod..."
    PROM_SCRAPE=$(kubectl exec -n observability $PROM_POD -- wget -q -O- --timeout=5 "http://${POD_IP}:20200/metrics" 2>/dev/null | head -5)
    if [ -n "$PROM_SCRAPE" ]; then
        echo -e "${GREEN}✓${NC} Prometheus can successfully scrape metrics!"
    else
        echo -e "${YELLOW}⚠${NC}  Prometheus cannot scrape metrics (may be NetworkPolicy issue)"
    fi
fi

# Cleanup
rm -f /tmp/consul-metrics-merging-patch.yaml

echo ""
echo "=========================================="
echo "Next Steps"
echo "=========================================="
echo ""
echo "1. Wait 1-2 minutes for Prometheus to scrape metrics"
echo ""
echo "2. Verify metrics in Prometheus:"
echo "   kubectl port-forward -n observability svc/prometheus-server 9090:80"
echo "   Query: envoy_cluster_upstream_rq_total{namespace=\"tracing-demo\"}"
echo ""
echo "3. Check Consul UI for metrics:"
echo "   https://consul-ui-consul.apps.rosa.cluster1.6cxo.p3.openshiftapps.com"
echo "   Navigate to: Services → [service] → Metrics"
echo ""
echo "4. Verify Grafana dashboards populate with data"
echo ""
echo "5. Generate traffic to see metrics:"
echo "   cd loadtest && ./simple-load.sh"
echo ""

# Made with Bob
