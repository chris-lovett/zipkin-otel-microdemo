#!/bin/bash

# Troubleshooting script for "No Data" in Consul UI and Grafana
# This script performs step-by-step diagnostics to identify why metrics aren't showing

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

NAMESPACE="tracing-demo"
CONSUL_NAMESPACE="consul"
OBSERVABILITY_NAMESPACE="observability"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Consul Metrics Troubleshooting Script${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Function to print status
print_status() {
    local status=$1
    local message=$2
    if [ "$status" == "OK" ]; then
        echo -e "${GREEN}✓${NC} $message"
    elif [ "$status" == "WARN" ]; then
        echo -e "${YELLOW}⚠${NC} $message"
    else
        echo -e "${RED}✗${NC} $message"
    fi
}

# Function to print section header
print_section() {
    echo ""
    echo -e "${BLUE}=== $1 ===${NC}"
}

# Step 1: Check if services are deployed
print_section "Step 1: Checking Service Deployment"

SERVICES=("frontend" "catalog" "cart" "checkout")
ALL_DEPLOYED=true

for svc in "${SERVICES[@]}"; do
    if kubectl get deployment -n $NAMESPACE $svc &>/dev/null; then
        REPLICAS=$(kubectl get deployment -n $NAMESPACE $svc -o jsonpath='{.status.readyReplicas}')
        DESIRED=$(kubectl get deployment -n $NAMESPACE $svc -o jsonpath='{.spec.replicas}')
        if [ "$REPLICAS" == "$DESIRED" ] && [ "$REPLICAS" != "" ]; then
            print_status "OK" "Service $svc: $REPLICAS/$DESIRED pods ready"
        else
            print_status "FAIL" "Service $svc: $REPLICAS/$DESIRED pods ready"
            ALL_DEPLOYED=false
        fi
    else
        print_status "FAIL" "Service $svc: not found"
        ALL_DEPLOYED=false
    fi
done

if [ "$ALL_DEPLOYED" = false ]; then
    echo ""
    echo -e "${RED}Some services are not deployed or not ready.${NC}"
    echo "Run: kubectl get pods -n $NAMESPACE"
    exit 1
fi

# Step 2: Check if traffic is flowing
print_section "Step 2: Checking for Traffic"

echo "Attempting to access frontend service..."
FRONTEND_POD=$(kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=frontend -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -z "$FRONTEND_POD" ]; then
    print_status "FAIL" "No frontend pod found"
    exit 1
fi

# Try to curl the frontend from within the pod
echo "Testing frontend accessibility..."
if kubectl exec -n $NAMESPACE $FRONTEND_POD -c frontend -- wget -q -O- --timeout=5 http://localhost:8080 &>/dev/null; then
    print_status "OK" "Frontend service is accessible"
else
    print_status "WARN" "Frontend service may not be responding"
fi

# Check Envoy stats for request counts
echo "Checking Envoy request statistics..."
REQUEST_COUNT=$(kubectl exec -n $NAMESPACE $FRONTEND_POD -c consul-dataplane -- wget -q -O- http://localhost:19000/stats 2>/dev/null | grep "http.ingress_http.downstream_rq_total" | awk '{print $2}' || echo "0")

if [ "$REQUEST_COUNT" -gt 0 ]; then
    print_status "OK" "Envoy has processed $REQUEST_COUNT requests"
else
    print_status "WARN" "Envoy shows 0 requests - NO TRAFFIC FLOWING"
    echo ""
    echo -e "${YELLOW}This is likely why you see '0 RPS' in Consul UI!${NC}"
    echo ""
    echo "To generate traffic, run:"
    echo "  cd loadtest && ./simple-load.sh"
    echo ""
    read -p "Would you like to generate test traffic now? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Starting load test..."
        cd "$REPO_ROOT/loadtest"
        ./simple-load.sh &
        LOAD_PID=$!
        echo "Load test started with PID: $LOAD_PID"
        echo "Generating traffic for 30 seconds..."
        sleep 30
        kill $LOAD_PID 2>/dev/null || true
        echo "Load test stopped. Continuing diagnostics..."
        cd ..
    else
        echo "Skipping traffic generation. Continuing diagnostics..."
    fi
fi

# Step 3: Check metrics endpoint
print_section "Step 3: Checking Metrics Endpoint (Port 20200)"

echo "Testing metrics endpoint on frontend pod..."
METRICS_OUTPUT=$(kubectl exec -n $NAMESPACE $FRONTEND_POD -c consul-dataplane -- wget -q -O- http://localhost:20200/metrics 2>/dev/null || echo "")

if [ -n "$METRICS_OUTPUT" ]; then
    METRIC_COUNT=$(echo "$METRICS_OUTPUT" | grep -c "^envoy_" || echo "0")
    if [ "$METRIC_COUNT" -gt 0 ]; then
        print_status "OK" "Metrics endpoint returns $METRIC_COUNT Envoy metrics"
    else
        print_status "WARN" "Metrics endpoint responds but no Envoy metrics found"
    fi
else
    print_status "FAIL" "Metrics endpoint (port 20200) returns nothing"
    echo ""
    echo -e "${RED}Metrics merging is not configured properly!${NC}"
    echo ""
    echo "To fix this, run:"
    echo "  ./scripts/observability/fix-metrics-merging.sh"
    echo ""
    read -p "Would you like to run the fix now? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        "$SCRIPT_DIR/fix-metrics-merging.sh"
        echo ""
        echo "Fix applied. Please wait 1-2 minutes for pods to restart, then run this script again."
        exit 0
    else
        exit 1
    fi
fi

# Step 4: Check Prometheus annotations
print_section "Step 4: Checking Prometheus Annotations"

ANNOTATIONS=$(kubectl get pod -n $NAMESPACE $FRONTEND_POD -o jsonpath='{.metadata.annotations}')

if echo "$ANNOTATIONS" | grep -q "prometheus.io/scrape.*true"; then
    print_status "OK" "prometheus.io/scrape: true"
else
    print_status "FAIL" "prometheus.io/scrape annotation missing or false"
fi

if echo "$ANNOTATIONS" | grep -q "prometheus.io/port.*20200"; then
    print_status "OK" "prometheus.io/port: 20200"
else
    print_status "WARN" "prometheus.io/port annotation not set to 20200"
fi

if echo "$ANNOTATIONS" | grep -q "prometheus.io/path.*/metrics"; then
    print_status "OK" "prometheus.io/path: /metrics"
else
    print_status "WARN" "prometheus.io/path annotation not set to /metrics"
fi

# Step 5: Check Prometheus connectivity
print_section "Step 5: Checking Prometheus"

if kubectl get svc -n $OBSERVABILITY_NAMESPACE prometheus-server &>/dev/null; then
    print_status "OK" "Prometheus service exists"
    
    # Check if Prometheus can reach the pod
    echo "Testing if Prometheus can scrape metrics..."
    
    # Get pod IP
    POD_IP=$(kubectl get pod -n $NAMESPACE $FRONTEND_POD -o jsonpath='{.status.podIP}')
    
    # Try to scrape from Prometheus pod
    PROM_POD=$(kubectl get pods -n $OBSERVABILITY_NAMESPACE -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    
    if [ -n "$PROM_POD" ]; then
        if kubectl exec -n $OBSERVABILITY_NAMESPACE $PROM_POD -- wget -q -O- --timeout=5 http://$POD_IP:20200/metrics &>/dev/null; then
            print_status "OK" "Prometheus can reach pod metrics endpoint"
        else
            print_status "FAIL" "Prometheus cannot reach pod metrics endpoint"
            echo ""
            echo -e "${RED}Network connectivity issue between Prometheus and application pods!${NC}"
            echo "Check NetworkPolicies:"
            echo "  kubectl get networkpolicy -n $NAMESPACE"
            echo "  kubectl get networkpolicy -n $OBSERVABILITY_NAMESPACE"
        fi
    else
        print_status "WARN" "Prometheus pod not found"
    fi
else
    print_status "FAIL" "Prometheus service not found in $OBSERVABILITY_NAMESPACE namespace"
fi

# Step 6: Check Consul UI configuration
print_section "Step 6: Checking Consul UI Configuration"

CONSUL_POD=$(kubectl get pods -n $CONSUL_NAMESPACE -l component=server -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -n "$CONSUL_POD" ]; then
    UI_CONFIG=$(kubectl exec -n $CONSUL_NAMESPACE $CONSUL_POD -- cat /consul/config/server.json 2>/dev/null | grep -A 10 "ui_config" || echo "")
    
    if echo "$UI_CONFIG" | grep -q "metrics_provider"; then
        print_status "OK" "Consul UI has metrics_provider configured"
    else
        print_status "FAIL" "Consul UI metrics_provider not configured"
        echo ""
        echo "To fix this, run:"
        echo "  ./fix-consul-ui-metrics-v2.sh"
    fi
    
    if echo "$UI_CONFIG" | grep -q "metrics_proxy"; then
        print_status "OK" "Consul UI has metrics_proxy configured"
    else
        print_status "FAIL" "Consul UI metrics_proxy not configured"
    fi
else
    print_status "WARN" "Consul server pod not found"
fi

# Step 7: Summary and recommendations
print_section "Summary and Recommendations"

echo ""
echo "Based on the diagnostics above:"
echo ""

if [ "$REQUEST_COUNT" -eq 0 ]; then
    echo -e "${YELLOW}PRIMARY ISSUE: No traffic flowing through services${NC}"
    echo ""
    echo "This is why you see '0 RPS' in Consul UI and 'No data' in Grafana."
    echo ""
    echo "SOLUTION:"
    echo "  1. Generate traffic using the load test:"
    echo "     cd loadtest && ./simple-load.sh"
    echo ""
    echo "  2. Wait 1-2 minutes for Prometheus to scrape metrics"
    echo ""
    echo "  3. Refresh Consul UI and Grafana dashboards"
    echo ""
else
    echo -e "${GREEN}Traffic is flowing ($REQUEST_COUNT requests processed)${NC}"
    echo ""
    echo "If you still see 'No data' in Grafana:"
    echo "  1. Check Grafana time range (try 'Last 1 hour')"
    echo "  2. Verify namespace filter is set to 'tracing-demo'"
    echo "  3. Check Prometheus data source configuration"
    echo ""
fi

echo "For detailed troubleshooting steps, see:"
echo "  TROUBLESHOOTING_NO_METRICS.md"
echo ""

# Made with Bob
