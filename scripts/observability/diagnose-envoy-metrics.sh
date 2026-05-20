#!/bin/bash

# Comprehensive Envoy Metrics Diagnostic Script
# Diagnoses why Envoy/consul-dataplane metrics are not being exposed

set -u

pod_http_get() {
    local namespace="$1"
    local pod="$2"
    local container="$3"
    local url="$4"
    kubectl exec -n "$namespace" "$pod" -c "$container" -- sh -c "if command -v wget >/dev/null 2>&1; then wget -q -O- --timeout=2 '$url'; elif command -v curl >/dev/null 2>&1; then curl -sf --max-time 2 '$url'; else exit 127; fi" 2>/dev/null
}

METRICS_COUNT=0
SCRAPE_OK=0

echo "=========================================="
echo "Envoy Metrics Comprehensive Diagnostics"
echo "=========================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

NAMESPACE="tracing-demo"
POD_NAME=$(kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=frontend -o jsonpath='{.items[0].metadata.name}')

if [ -z "$POD_NAME" ]; then
    echo -e "${RED}✗${NC} Could not find frontend pod in namespace $NAMESPACE"
    exit 1
fi

echo -e "${GREEN}✓${NC} Using pod: $POD_NAME"
echo ""

# Step 1: Check pod annotations
echo "=========================================="
echo "Step 1: Checking Prometheus Annotations"
echo "=========================================="
kubectl get pod -n $NAMESPACE $POD_NAME -o yaml | grep -A 3 "prometheus.io"
echo ""

# Step 2: Check containers in pod
echo "=========================================="
echo "Step 2: Checking Pod Containers"
echo "=========================================="
echo "Containers in pod:"
kubectl get pod -n $NAMESPACE $POD_NAME -o jsonpath='{.spec.containers[*].name}'
echo ""
echo ""

# Step 3: Check consul-dataplane container ports
echo "=========================================="
echo "Step 3: Checking consul-dataplane Ports"
echo "=========================================="
kubectl get pod -n $NAMESPACE $POD_NAME -o json | jq -r '.spec.containers[] | select(.name=="consul-dataplane") | .ports[]? | "\(.name): \(.containerPort)"'
echo ""

# Step 4: Test different Envoy admin endpoints
echo "=========================================="
echo "Step 4: Testing Envoy Admin Endpoints"
echo "=========================================="

echo "Testing port 19000 (standard Envoy admin)..."
ADMIN_19000=$(pod_http_get "$NAMESPACE" "$POD_NAME" consul-dataplane http://localhost:19000/stats/prometheus | head -5)
if [ -n "$ADMIN_19000" ]; then
    echo -e "${GREEN}✓${NC} Port 19000 is accessible"
    echo "Sample metrics:"
    echo "$ADMIN_19000"
    METRICS_COUNT=$(pod_http_get "$NAMESPACE" "$POD_NAME" consul-dataplane http://localhost:19000/stats/prometheus | grep -c "envoy_" || echo "0")
    echo "Total Envoy metrics: $METRICS_COUNT"
else
    echo -e "${RED}✗${NC} Port 19000 not accessible or no metrics"
fi
echo ""

echo "Testing port 20200 (configured metrics port)..."
ADMIN_20200=$(pod_http_get "$NAMESPACE" "$POD_NAME" consul-dataplane http://localhost:20200/metrics | head -5)
if [ -n "$ADMIN_20200" ]; then
    echo -e "${GREEN}✓${NC} Port 20200 is accessible"
    echo "Sample metrics:"
    echo "$ADMIN_20200"
    METRICS_COUNT=$(pod_http_get "$NAMESPACE" "$POD_NAME" consul-dataplane http://localhost:20200/metrics | grep -c "envoy_" || echo "0")
    echo "Total Envoy metrics: $METRICS_COUNT"
else
    echo -e "${RED}✗${NC} Port 20200 not accessible or no metrics"
fi
echo ""

# Step 5: Check Envoy admin interface
echo "=========================================="
echo "Step 5: Checking Envoy Admin Interface"
echo "=========================================="
echo "Available admin endpoints:"
pod_http_get "$NAMESPACE" "$POD_NAME" consul-dataplane http://localhost:19000/help || echo "Admin interface not accessible on port 19000"
echo ""

# Step 6: Check consul-dataplane logs for metrics-related messages
echo "=========================================="
echo "Step 6: Checking consul-dataplane Logs"
echo "=========================================="
echo "Recent logs (last 50 lines):"
kubectl logs -n $NAMESPACE $POD_NAME -c consul-dataplane --tail=50 | grep -i -E "(metric|prometheus|admin|envoy)" || echo "No metrics-related log entries found"
echo ""

# Step 7: Check Consul connectInject configuration
echo "=========================================="
echo "Step 7: Checking Consul Helm Values"
echo "=========================================="
echo "connectInject.metrics configuration:"
helm get values consul -n consul -o json | jq '.connectInject.metrics'
echo ""

# Step 8: Check if metrics merging is enabled
echo "=========================================="
echo "Step 8: Checking Metrics Merging Config"
echo "=========================================="
MERGE_ANNOTATION=$(kubectl get pod -n $NAMESPACE $POD_NAME -o jsonpath='{.metadata.annotations.consul\.hashicorp\.com/enable-metrics-merging}' 2>/dev/null)
if [ -n "$MERGE_ANNOTATION" ]; then
    echo "consul.hashicorp.com/enable-metrics-merging=$MERGE_ANNOTATION"
else
    echo "No per-pod enable-metrics-merging annotation found (expected with defaultEnableMerging=false)."
fi
echo ""

# Step 9: Test Prometheus scraping
echo "=========================================="
echo "Step 9: Testing Prometheus Scrape"
echo "=========================================="
echo "Checking if Prometheus can reach the pod..."

# Get pod IP
POD_IP=$(kubectl get pod -n $NAMESPACE $POD_NAME -o jsonpath='{.status.podIP}')
echo "Pod IP: $POD_IP"

# Try to scrape from Prometheus
echo "Attempting to scrape metrics from Prometheus perspective..."
PROM_POD=$(kubectl get pods -n observability -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$PROM_POD" ]; then
    SCRAPE_SAMPLE=$(kubectl exec -n observability $PROM_POD -- sh -c "if command -v wget >/dev/null 2>&1; then wget -q -O- --timeout=2 'http://${POD_IP}:20200/metrics'; elif command -v curl >/dev/null 2>&1; then curl -sf --max-time 2 'http://${POD_IP}:20200/metrics'; else exit 127; fi" 2>/dev/null)
    if [ -n "$SCRAPE_SAMPLE" ]; then
        SCRAPE_OK=1
        echo "$SCRAPE_SAMPLE" | head -10
    else
        echo "Cannot scrape from Prometheus pod"
    fi
else
    echo "Prometheus pod not found"
fi
echo ""

# Step 10: Check for NetworkPolicies
echo "=========================================="
echo "Step 10: Checking NetworkPolicies"
echo "=========================================="
kubectl get networkpolicy -n $NAMESPACE -o yaml | grep -A 10 "kind: NetworkPolicy" || echo "No NetworkPolicies found in $NAMESPACE"
echo ""

# Step 11: Check Envoy bootstrap configuration
echo "=========================================="
echo "Step 11: Checking Envoy Bootstrap Config"
echo "=========================================="
echo "Looking for admin address configuration..."
kubectl exec -n $NAMESPACE $POD_NAME -c consul-dataplane -- cat /consul/connect-inject/envoy-bootstrap.json 2>/dev/null | jq '.admin' || echo "Cannot read Envoy bootstrap config"
echo ""

# Step 12: Summary and Recommendations
echo "=========================================="
echo "Summary and Recommendations"
echo "=========================================="
echo ""

if [ "$METRICS_COUNT" -gt "0" ] || [ "$SCRAPE_OK" -eq "1" ]; then
    echo -e "${GREEN}✓${NC} Envoy metrics ARE being exposed ($METRICS_COUNT metrics found)"
    echo ""
    echo "Next steps:"
    echo "1. Verify Prometheus is scraping the correct port"
    echo "2. Check Prometheus targets: kubectl port-forward -n observability svc/prometheus-server 9090:80"
    echo "   Then visit: http://localhost:9090/targets"
    echo "3. Verify metrics in Prometheus: query 'envoy_cluster_upstream_rq_total{namespace=\"tracing-demo\"}'"
else
    echo -e "${RED}✗${NC} Envoy metrics are NOT being exposed"
    echo ""
    echo "Possible causes:"
    echo "1. Envoy admin interface is disabled"
    echo "2. Metrics port is different than expected"
    echo "3. consul-dataplane is not configured to expose metrics"
    echo "4. Envoy bootstrap configuration is missing admin section"
    echo ""
    echo "Recommended fixes:"
    echo "1. Check Consul Helm values: helm get values consul -n consul"
    echo "2. Verify connectInject.metrics.defaultEnabled is true"
    echo "3. Check if pods need to be recreated after Helm upgrade"
    echo "4. Review consul-dataplane logs for errors"
fi

echo ""
echo "For detailed troubleshooting, see: CONSUL_METRICS.md"
echo ""

exit 0

# Made with Bob
