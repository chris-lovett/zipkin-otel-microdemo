#!/bin/bash
#
# Simple load generator for zipkin-otel-microdemo
# Generates realistic traffic patterns to create interesting distributed traces
#

set -e

# Configuration
FRONTEND_URL="${FRONTEND_URL:-https://frontend-tracing-demo.apps.rosa.cluster1.6cxo.p3.openshiftapps.com}"
DURATION="${DURATION:-60}"  # seconds
CONCURRENT="${CONCURRENT:-5}"  # concurrent users

PRODUCT_IDS=("prod-1" "prod-2" "prod-3" "prod-4" "prod-5" "prod-6" "prod-7" "prod-8")

random_product_id() {
    local index=$((RANDOM % ${#PRODUCT_IDS[@]}))
    echo "${PRODUCT_IDS[$index]}"
}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Zipkin OTel Microdemo Load Generator ===${NC}"
echo "Frontend URL: $FRONTEND_URL"
echo "Duration: ${DURATION}s"
echo "Concurrent users: $CONCURRENT"
echo ""

# Function to simulate a user browsing
browse_products() {
    local user_id=$1
    echo -e "${YELLOW}[User $user_id]${NC} Browsing products..."
    
    # List all products
    curl -s -o /dev/null -w "Browse products: %{http_code} (%{time_total}s)\n" \
        "$FRONTEND_URL/products"
    
    # View random product details
    local product_id
    product_id=$(random_product_id)
    curl -s -o /dev/null -w "View product $product_id: %{http_code} (%{time_total}s)\n" \
        "$FRONTEND_URL/products/$product_id"
    
    sleep $((RANDOM % 3 + 1))
}

# Function to simulate adding items to cart
add_to_cart() {
    local user_id=$1
    echo -e "${YELLOW}[User $user_id]${NC} Adding to cart..."
    
    # Browse first
    curl -s -o /dev/null "$FRONTEND_URL/products"
    
    # Add 1-3 items to cart
    local items=$((RANDOM % 3 + 1))
    for ((i=1; i<=items; i++)); do
        local product_id
        product_id=$(random_product_id)
        local quantity=$((RANDOM % 3 + 1))

        curl -s -o /dev/null -w "Add product $product_id (qty: $quantity): %{http_code} (%{time_total}s)\n" \
            -X POST "$FRONTEND_URL/cart/user${user_id}/items" \
            -H 'Content-Type: application/json' \
            -d "{\"product_id\":\"$product_id\",\"quantity\":$quantity}"
        
        sleep 1
    done
    
    sleep $((RANDOM % 2 + 1))
}

# Function to simulate checkout
checkout() {
    local user_id=$1
    echo -e "${YELLOW}[User $user_id]${NC} Checking out..."
    
    # Add items to cart first
    local product_id
    product_id=$(random_product_id)
    curl -s -o /dev/null -w "Seed cart with $product_id: %{http_code} (%{time_total}s)\n" \
        -X POST "$FRONTEND_URL/cart/user${user_id}/items" \
        -H 'Content-Type: application/json' \
        -d "{\"product_id\":\"$product_id\",\"quantity\":2}"

    sleep 1

    # Add a second valid item sometimes so checkout paths are richer
    if [ $((RANDOM % 2)) -eq 0 ]; then
        product_id=$(random_product_id)
        curl -s -o /dev/null -w "Add second product $product_id: %{http_code} (%{time_total}s)\n" \
            -X POST "$FRONTEND_URL/cart/user${user_id}/items" \
            -H 'Content-Type: application/json' \
            -d "{\"product_id\":\"$product_id\",\"quantity\":1}"
        sleep 1
    fi

    # Checkout
    curl -s -o /dev/null -w "Checkout: %{http_code} (%{time_total}s)\n" \
        -X POST "$FRONTEND_URL/checkout" \
        -H 'Content-Type: application/json' \
        -d "{\"user_id\":\"user${user_id}\"}"
    
    sleep $((RANDOM % 3 + 1))
}

# Function to simulate a user session
user_session() {
    local user_id=$1
    local end_time=$2
    
    echo -e "${GREEN}[User $user_id]${NC} Starting session..."
    
    while [ $(date +%s) -lt $end_time ]; do
        # Random action: 50% browse, 30% add to cart, 20% checkout
        local action=$((RANDOM % 10))
        
        if [ $action -lt 5 ]; then
            browse_products $user_id
        elif [ $action -lt 8 ]; then
            add_to_cart $user_id
        else
            checkout $user_id
        fi
        
        # Random think time between actions
        sleep $((RANDOM % 5 + 2))
    done
    
    echo -e "${GREEN}[User $user_id]${NC} Session complete"
}

# Calculate end time
END_TIME=$(($(date +%s) + DURATION))

echo -e "${GREEN}Starting load test...${NC}"
echo "Press Ctrl+C to stop early"
echo ""

# Start concurrent user sessions in background
for ((i=1; i<=CONCURRENT; i++)); do
    user_session $i $END_TIME &
done

# Wait for all background jobs
wait

echo ""
echo -e "${GREEN}=== Load test complete ===${NC}"
echo "Check Zipkin UI for distributed traces:"
echo "https://zipkin-tracing-demo.apps.rosa.cluster1.6cxo.p3.openshiftapps.com"

# Made with Bob
