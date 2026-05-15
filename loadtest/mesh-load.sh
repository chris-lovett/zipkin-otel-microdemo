#!/bin/bash

# Load test script that generates traffic THROUGH the Consul service mesh
# This ensures Envoy proxies process the requests and generate metrics

set -e

NAMESPACE="${NAMESPACE:-tracing-demo}"
DURATION="${DURATION:-60}"
CONCURRENT="${CONCURRENT:-5}"

echo "=========================================="
echo "Consul Service Mesh Load Test"
echo "=========================================="
echo "Namespace: $NAMESPACE"
echo "Duration: ${DURATION}s"
echo "Concurrent users: $CONCURRENT"
echo ""
echo "This script generates traffic INSIDE the mesh"
echo "so that Envoy metrics are generated."
echo ""

# Function to simulate a user session
simulate_user() {
    local user_id=$1
    local end_time=$((SECONDS + DURATION))
    
    echo "[User $user_id] Starting session..."
    
    while [ $SECONDS -lt $end_time ]; do
        local action=$((RANDOM % 3))
        
        case $action in
            0)
                # Browse products
                echo "[User $user_id] Browsing products..."
                kubectl exec -n $NAMESPACE deployment/frontend -c frontend -- \
                    wget -q -O- --timeout=5 http://localhost:8080/products >/dev/null 2>&1 && \
                    echo "Browse products: 200" || echo "Browse products: failed"
                ;;
            1)
                # View product details
                local product_id=$((RANDOM % 10 + 1))
                echo "[User $user_id] Viewing product $product_id..."
                kubectl exec -n $NAMESPACE deployment/frontend -c frontend -- \
                    wget -q -O- --timeout=5 http://localhost:8080/products/$product_id >/dev/null 2>&1 && \
                    echo "View product $product_id: 200" || echo "View product $product_id: 404"
                ;;
            2)
                # Add to cart
                local product_id=$((RANDOM % 10 + 1))
                local quantity=$((RANDOM % 3 + 1))
                echo "[User $user_id] Adding product $product_id (qty: $quantity) to cart..."
                kubectl exec -n $NAMESPACE deployment/frontend -c frontend -- \
                    wget -q -O- --timeout=5 --post-data="{\"product_id\":\"$product_id\",\"quantity\":$quantity}" \
                    --header='Content-Type: application/json' \
                    http://localhost:8080/cart/user${user_id}/items >/dev/null 2>&1 && \
                    echo "Add to cart: 200" || echo "Add to cart: failed"
                ;;
        esac
        
        sleep $((RANDOM % 3 + 1))
    done
    
    echo "[User $user_id] Session complete"
}

# Check if frontend deployment exists
if ! kubectl get deployment -n $NAMESPACE frontend &>/dev/null; then
    echo "ERROR: frontend deployment not found in namespace $NAMESPACE"
    exit 1
fi

# Check if frontend pod is ready
READY=$(kubectl get deployment -n $NAMESPACE frontend -o jsonpath='{.status.readyReplicas}')
if [ "$READY" != "1" ]; then
    echo "ERROR: frontend deployment is not ready (ready replicas: $READY)"
    exit 1
fi

echo "Starting $CONCURRENT concurrent users..."
echo ""

# Start concurrent user sessions
for i in $(seq 1 $CONCURRENT); do
    simulate_user $i &
done

# Wait for all background jobs to complete
wait

echo ""
echo "=========================================="
echo "Load test complete!"
echo "=========================================="
echo ""
echo "Traffic was generated THROUGH the service mesh."
echo "Envoy metrics should now be available."
echo ""
echo "Next steps:"
echo "1. Wait 1-2 minutes for Prometheus to scrape metrics"
echo "2. Refresh Consul UI - you should see RPS > 0"
echo "3. Check Grafana dashboards - should show data"
echo ""
echo "To verify metrics are being generated:"
echo "  kubectl exec -n $NAMESPACE deployment/frontend -c consul-dataplane -- \\"
echo "    wget -q -O- http://localhost:20200/metrics | grep envoy_cluster_upstream_rq_total"
echo ""

# Made with Bob
