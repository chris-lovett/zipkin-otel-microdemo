# Load Testing Tools

This directory contains various load testing tools to generate interesting distributed traces in the zipkin-otel-microdemo application.

## Available Tools

### 1. Simple Bash Load Generator (`simple-load.sh`)

A lightweight bash script for quick load testing without dependencies.

**Features:**
- No dependencies (just bash and curl)
- Simulates realistic user behavior
- Multiple concurrent users
- Random traffic patterns

**Usage:**
```bash
# Basic usage (60s, 5 users)
./simple-load.sh

# Custom duration and concurrency
DURATION=120 CONCURRENT=10 ./simple-load.sh

# Custom frontend URL
FRONTEND_URL=https://your-frontend-url.com ./simple-load.sh
```

**Environment Variables:**
- `FRONTEND_URL` - Frontend service URL (default: production URL)
- `DURATION` - Test duration in seconds (default: 60)
- `CONCURRENT` - Number of concurrent users (default: 5)

### 2. Advanced Python Load Generator (`advanced-load.py`)

A sophisticated Python-based load generator with multiple scenarios and statistics.

**Features:**
- Multiple traffic scenarios
- Detailed statistics
- Configurable user behavior
- Thread-based concurrency

**Requirements:**
```bash
pip install requests
```

**Usage:**
```bash
# Basic usage (mixed scenario, 60s, 5 users)
./advanced-load.py

# Browse-heavy traffic (users mostly browsing)
./advanced-load.py --scenario browse --users 10 --duration 120

# Buy-heavy traffic (users frequently checking out)
./advanced-load.py --scenario buy --users 5 --duration 90

# Spike traffic (high frequency, minimal delays)
./advanced-load.py --scenario spike --users 20 --duration 30

# Custom URL
./advanced-load.py --url https://your-frontend-url.com
```

**Scenarios:**
- `mixed` (default) - Balanced traffic: 50% browse, 30% cart, 20% checkout
- `browse` - Browse-heavy: 70% browse, 20% cart, 10% checkout
- `buy` - Purchase-heavy: 30% browse, 30% cart, 40% checkout
- `spike` - High-frequency traffic with minimal delays

**Options:**
- `--url URL` - Frontend URL
- `--duration SECONDS` - Test duration (default: 60)
- `--users COUNT` - Concurrent users (default: 5)
- `--scenario SCENARIO` - Traffic pattern (default: mixed)

### 3. k6 Load Testing (`k6/script.js`)

Professional load testing with k6 for advanced scenarios.

**Requirements:**
```bash
# Install k6
brew install k6  # macOS
# or download from https://k6.io/docs/getting-started/installation/
```

**Usage:**
```bash
# Run k6 test
k6 run -e BASE_URL=https://frontend-tracing-demo.apps.rosa.cluster1.6cxo.p3.openshiftapps.com k6/script.js

# With custom VUs and duration
k6 run --vus 10 --duration 2m -e BASE_URL=https://your-url.com k6/script.js
```

## Trace Patterns Generated

### Browse Products
Creates simple 2-service traces:
```
frontend → catalog
```

### Add to Cart
Creates 3-service traces:
```
frontend → cart → catalog
```

### Checkout
Creates complex 5-service traces:
```
frontend → checkout → cart
                   → inventory
                   → payment
```

## Viewing Traces in Zipkin

After running load tests, view traces at:
```
https://zipkin-tracing-demo.apps.rosa.cluster1.6cxo.p3.openshiftapps.com
```

### Interesting Queries

1. **Find slow checkouts:**
   - Service: `checkout`
   - Min Duration: `500ms`

2. **Find all cart operations:**
   - Service: `cart`

3. **Find traces with errors:**
   - Tags: `error=true`

4. **Find long traces (many services):**
   - Min Duration: `200ms`
   - Look for traces with 5+ spans

## Tips for Interesting Traces

1. **Generate diverse traffic:**
   ```bash
   # Run multiple scenarios simultaneously
   ./advanced-load.py --scenario browse --users 5 --duration 120 &
   ./advanced-load.py --scenario buy --users 3 --duration 120 &
   wait
   ```

2. **Create spike patterns:**
   ```bash
   # Normal traffic
   ./simple-load.sh &
   sleep 30
   # Spike
   ./advanced-load.py --scenario spike --users 20 --duration 20
   ```

3. **Test with payment failures:**
   ```bash
   # Enable payment failures (if admin endpoint is exposed)
   curl -X POST http://payment-service/admin/config \
     -H 'Content-Type: application/json' \
     -d '{"failure_rate":0.3,"latency_ms":500}'
   
   # Then run load test
   ./advanced-load.py --scenario buy --users 10
   ```

4. **Long-running background load:**
   ```bash
   # Run for 10 minutes with moderate load
   DURATION=600 CONCURRENT=3 ./simple-load.sh
   ```

## Consul Service Mesh Traces

With Consul Service Mesh enabled, each service call generates **two spans**:

1. **Envoy ingress span** - Sidecar proxy overhead
2. **Application span** - Business logic execution

This creates rich traces showing:
- mTLS handshake time
- Proxy routing overhead
- Application processing time
- Service-to-service latency

## Troubleshooting

### Connection Errors
```bash
# Verify frontend is accessible
curl https://frontend-tracing-demo.apps.rosa.cluster1.6cxo.p3.openshiftapps.com/products

# Check route
oc get route frontend -n tracing-demo
```

### No Traces Appearing
1. Check Zipkin is running: `kubectl get pods -n tracing-demo`
2. Verify ZIPKIN_URL in service configs
3. Check service logs for errors

### Python Script Errors
```bash
# Install dependencies
pip install requests

# Or use virtual environment
python3 -m venv venv
source venv/bin/activate
pip install requests
./advanced-load.py
```

## Example Workflows

### Quick Test
```bash
# 30 second test with 3 users
DURATION=30 CONCURRENT=3 ./simple-load.sh
```

### Comprehensive Test
```bash
# 5 minute test with varied traffic
./advanced-load.py --scenario mixed --users 10 --duration 300
```

### Stress Test
```bash
# High load for 2 minutes
./advanced-load.py --scenario spike --users 30 --duration 120
```

### Realistic Simulation
```bash
# Simulate 20 users over 10 minutes with mixed behavior
./advanced-load.py --scenario mixed --users 20 --duration 600