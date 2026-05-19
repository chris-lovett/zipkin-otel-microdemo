#!/bin/bash
# Continuous load generator for API Gateway dashboard testing

echo "Starting continuous load generator for API Gateway..."
echo "Press Ctrl+C to stop"
echo ""

# Counter for requests
count=0

while true; do
    # Generate a mix of traffic patterns
    
    # 70% successful requests
    for i in {1..7}; do
        kubectl exec -n tracing-demo deployment/frontend -- wget -qO- http://api-gateway:8080/products > /dev/null 2>&1 &
    done
    
    # 20% product detail requests
    for i in {1..2}; do
        kubectl exec -n tracing-demo deployment/frontend -- wget -qO- http://api-gateway:8080/products/1 > /dev/null 2>&1 &
    done
    
    # 10% cart operations (may generate some errors if cart is empty)
    kubectl exec -n tracing-demo deployment/frontend -- wget -qO- http://api-gateway:8080/cart/user123 > /dev/null 2>&1 &
    
    count=$((count + 10))
    echo "Generated $count requests..."
    
    # Wait 2 seconds between batches (5 req/sec average)
    sleep 2
done

# Made with Bob
