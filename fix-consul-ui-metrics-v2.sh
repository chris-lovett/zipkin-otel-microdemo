#!/bin/bash

# Fix Consul UI Metrics Configuration (Version 2)
# This script adds ui_config to Consul server configuration via extraConfig

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

# Step 2: Get current server.extraConfig
echo ""
echo "Step 2: Getting current Consul server extraConfig..."
CURRENT_EXTRA_CONFIG=$(helm get values consul -n consul -o json | jq -r '.server.extraConfig // "{}"')
echo "Current extraConfig:"
echo "$CURRENT_EXTRA_CONFIG"

# Step 3: Create new extraConfig with ui_config merged
echo ""
echo "Step 3: Creating updated extraConfig with ui_config..."

# Parse existing extraConfig and add ui_config
cat > /tmp/consul-server-config.json <<EOF
{
  "verify_incoming_rpc": true,
  "verify_incoming_https": false,
  "verify_outgoing": true,
  "verify_server_hostname": true,
  "ui_config": {
    "enabled": true,
    "metrics_provider": "prometheus",
    "metrics_proxy": {
      "base_url": "${PROM_URL}"
    }
  }
}
EOF

echo "New server configuration:"
cat /tmp/consul-server-config.json | jq .
echo ""

# Step 4: Create Helm values patch
echo "Step 4: Creating Helm values patch..."

cat > /tmp/consul-metrics-patch.yaml <<EOF
server:
  extraConfig: |
$(cat /tmp/consul-server-config.json | sed 's/^/    /')

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

echo -e "${GREEN}✓${NC} Created Helm values patch"
echo ""
echo "Patch contents:"
cat /tmp/consul-metrics-patch.yaml
echo ""

# Step 5: Get current Consul Helm release info
echo "Step 5: Getting current Consul Helm release info..."
CONSUL_RELEASE=$(helm list -n consul -o json | jq -r '.[0].name')
CONSUL_CHART=$(helm list -n consul -o json | jq -r '.[0].chart')

if [ -z "$CONSUL_RELEASE" ] || [ "$CONSUL_RELEASE" == "null" ]; then
    echo -e "${RED}✗${NC} Could not find Consul Helm release in consul namespace"
    exit 1
fi

echo -e "${GREEN}✓${NC} Found Consul release: $CONSUL_RELEASE (chart: $CONSUL_CHART)"

# Step 6: Apply Helm upgrade
echo ""
echo "Step 6: Applying Helm upgrade with ui_config in extraConfig..."
echo -e "${YELLOW}This will update the Consul Helm release and restart servers...${NC}"

helm upgrade "$CONSUL_RELEASE" hashicorp/consul \
    --namespace consul \
    --reuse-values \
    --values /tmp/consul-metrics-patch.yaml

echo -e "${GREEN}✓${NC} Helm upgrade completed"

# Step 7: Wait for Consul servers to restart
echo ""
echo "Step 7: Waiting for Consul servers to be ready..."
kubectl rollout status statefulset/consul-server -n consul --timeout=300s

echo -e "${GREEN}✓${NC} Consul servers are ready"

# Step 8: Verify ui_config is now present
echo ""
echo "Step 8: Verifying ui_config in Consul server configuration..."
sleep 10  # Give servers a moment to fully initialize

UI_CONFIG=$(kubectl exec -n consul consul-server-0 -- cat /consul/config/server.json 2>/dev/null | jq '.ui_config')
if [ "$UI_CONFIG" != "null" ] && [ -n "$UI_CONFIG" ]; then
    echo -e "${GREEN}✓${NC} ui_config found in server configuration!"
    echo ""
    echo "UI Config:"
    echo "$UI_CONFIG" | jq .
else
    echo -e "${RED}✗${NC} ui_config still not found in server.json"
    echo "Checking all config files..."
    kubectl exec -n consul consul-server-0 -- ls -la /consul/config/
fi

# Step 9: Test Prometheus connectivity from Consul
echo ""
echo "Step 9: Testing Prometheus connectivity from Consul server..."
PROM_TEST=$(kubectl exec -n consul consul-server-0 -- wget -q -O- --timeout=5 "${PROM_URL}/api/v1/query?query=up" 2>/dev/null)

if echo "$PROM_TEST" | grep -q '"status":"success"'; then
    echo -e "${GREEN}✓${NC} Consul can reach Prometheus successfully"
else
    echo -e "${RED}✗${NC} Consul cannot reach Prometheus"
    echo "Response: $PROM_TEST"
fi

# Step 10: Test metrics proxy endpoint
echo ""
echo "Step 10: Testing Consul metrics proxy endpoint..."
echo "Attempting to query metrics through Consul UI proxy..."

# Port forward in background
kubectl port-forward -n consul svc/consul-ui 8500:443 &>/dev/null &
PF_PID=$!
sleep 3

# Test the metrics proxy endpoint
METRICS_TEST=$(curl -k -s "https://localhost:8500/v1/internal/ui/metrics-proxy/api/v1/query?query=up" 2>/dev/null || echo "failed")

if echo "$METRICS_TEST" | grep -q '"status":"success"'; then
    echo -e "${GREEN}✓${NC} Consul UI metrics proxy is working!"
else
    echo -e "${YELLOW}⚠${NC}  Metrics proxy test inconclusive"
    echo "Response: $METRICS_TEST"
fi

# Cleanup port forward
kill $PF_PID 2>/dev/null || true

# Cleanup temp files
rm -f /tmp/consul-server-config.json /tmp/consul-metrics-patch.yaml

echo ""
echo "=========================================="
echo "Next Steps"
echo "=========================================="
echo ""
echo "1. Access Consul UI via OpenShift route:"
echo "   https://consul-ui-consul.apps.rosa.cluster1.6cxo.p3.openshiftapps.com"
echo ""
echo "2. Navigate to Services → [service name] → Metrics tab"
echo ""
echo "3. If metrics still don't appear:"
echo "   a. Check browser console for errors (F12)"
echo "   b. Verify the metrics proxy endpoint:"
echo "      curl -k 'https://consul-ui-consul.apps.rosa.cluster1.6cxo.p3.openshiftapps.com/v1/internal/ui/metrics-proxy/api/v1/query?query=up'"
echo "   c. Generate traffic: cd loadtest && ./simple-load.sh"
echo "   d. Check Consul server logs:"
echo "      kubectl logs -n consul consul-server-0 | grep -i metrics"
echo ""
echo "4. For detailed troubleshooting, see: CONSUL_METRICS.md"
echo ""

# Made with Bob
