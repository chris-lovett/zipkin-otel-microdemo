#!/bin/bash

# Fix Consul UI Metrics Configuration
# This script updates the Consul Helm release with proper metrics configuration

set -e

echo "=========================================="
echo "Fixing Consul UI Metrics Configuration"
echo "=========================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Step 1: Verify Prometheus is accessible
echo "Step 1: Verifying Prometheus service..."
if kubectl get svc -n observability prometheus-server &>/dev/null; then
    echo -e "${GREEN}✓${NC} Prometheus service found in observability namespace"
    PROM_URL="http://prometheus-server.observability.svc.cluster.local"
else
    echo -e "${RED}✗${NC} Prometheus service not found in observability namespace"
    exit 1
fi

# Step 2: Create Helm values patch file
echo ""
echo "Step 2: Creating Helm values patch..."

cat > /tmp/consul-metrics-patch.yaml <<EOF
ui:
  enabled: true
  service:
    enabled: true
  metrics:
    enabled: true
    provider: "prometheus"
    baseURL: "${PROM_URL}"

connectInject:
  enabled: true
  default: true
  transparentProxy:
    defaultEnabled: true
  metrics:
    defaultEnabled: true
    defaultEnableMerging: true
    enableGatewayMetrics: true
EOF

echo -e "${GREEN}✓${NC} Created Helm values patch at /tmp/consul-metrics-patch.yaml"
echo ""
echo "Patch contents:"
cat /tmp/consul-metrics-patch.yaml
echo ""

# Step 3: Get current Consul Helm release info
echo "Step 3: Getting current Consul Helm release info..."
CONSUL_RELEASE=$(helm list -n consul -o json | jq -r '.[0].name')
CONSUL_CHART=$(helm list -n consul -o json | jq -r '.[0].chart')

if [ -z "$CONSUL_RELEASE" ] || [ "$CONSUL_RELEASE" == "null" ]; then
    echo -e "${RED}✗${NC} Could not find Consul Helm release in consul namespace"
    exit 1
fi

echo -e "${GREEN}✓${NC} Found Consul release: $CONSUL_RELEASE (chart: $CONSUL_CHART)"

# Step 4: Apply Helm upgrade
echo ""
echo "Step 4: Applying Helm upgrade with metrics configuration..."
echo -e "${YELLOW}This will update the Consul Helm release...${NC}"

helm upgrade "$CONSUL_RELEASE" hashicorp/consul \
    --namespace consul \
    --reuse-values \
    --values /tmp/consul-metrics-patch.yaml

echo -e "${GREEN}✓${NC} Helm upgrade completed"

# Step 5: Wait for Consul servers to restart
echo ""
echo "Step 5: Waiting for Consul servers to be ready..."
kubectl rollout status statefulset/consul-server -n consul --timeout=300s

echo -e "${GREEN}✓${NC} Consul servers are ready"

# Step 6: Verify ui_config is now present
echo ""
echo "Step 6: Verifying ui_config in Consul server configuration..."
sleep 10  # Give servers a moment to fully initialize

UI_CONFIG=$(kubectl exec -n consul consul-server-0 -- consul operator raft list-peers 2>/dev/null | head -1)
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓${NC} Consul servers are responding"
    
    # Check if ui_config is in the server's configuration
    kubectl exec -n consul consul-server-0 -- cat /consul/config/server.json | grep -q "ui_config"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓${NC} ui_config found in server configuration!"
        echo ""
        echo "UI Config section:"
        kubectl exec -n consul consul-server-0 -- cat /consul/config/server.json | jq '.ui_config' 2>/dev/null || echo "Could not parse JSON"
    else
        echo -e "${YELLOW}⚠${NC}  ui_config not found in server.json"
        echo "This may require manual configuration via ConfigMap"
    fi
else
    echo -e "${YELLOW}⚠${NC}  Could not verify Consul server status"
fi

# Step 7: Test Prometheus connectivity from Consul
echo ""
echo "Step 7: Testing Prometheus connectivity from Consul server..."
PROM_TEST=$(kubectl exec -n consul consul-server-0 -- wget -q -O- --timeout=5 "${PROM_URL}/api/v1/query?query=up" 2>/dev/null)

if echo "$PROM_TEST" | grep -q '"status":"success"'; then
    echo -e "${GREEN}✓${NC} Consul can reach Prometheus successfully"
else
    echo -e "${RED}✗${NC} Consul cannot reach Prometheus"
    echo "Response: $PROM_TEST"
fi

# Step 8: Verify Envoy metrics are available
echo ""
echo "Step 8: Checking if Prometheus has Envoy metrics..."
ENVOY_METRICS=$(kubectl exec -n consul consul-server-0 -- wget -q -O- --timeout=5 "${PROM_URL}/api/v1/query?query=envoy_cluster_upstream_rq_total" 2>/dev/null)

if echo "$ENVOY_METRICS" | grep -q '"status":"success"'; then
    METRIC_COUNT=$(echo "$ENVOY_METRICS" | jq '.data.result | length' 2>/dev/null || echo "0")
    echo -e "${GREEN}✓${NC} Prometheus has Envoy metrics (found $METRIC_COUNT series)"
else
    echo -e "${YELLOW}⚠${NC}  No Envoy metrics found in Prometheus"
    echo "You may need to generate traffic or check Prometheus scrape configuration"
fi

# Cleanup
rm -f /tmp/consul-metrics-patch.yaml

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
echo "   a. Check browser console for errors"
echo "   b. Verify Prometheus targets: kubectl port-forward -n observability svc/prometheus-server 9090:80"
echo "      Then open: http://localhost:9090/targets"
echo "   c. Generate traffic: cd loadtest && ./simple-load.sh"
echo "   d. Check Consul logs: kubectl logs -n consul consul-server-0 | grep -i metrics"
echo ""
echo "4. For detailed troubleshooting, see: CONSUL_METRICS.md"
echo ""

# Made with Bob
