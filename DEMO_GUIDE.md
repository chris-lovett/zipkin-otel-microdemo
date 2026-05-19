# Distributed Tracing Demo Guide

This guide provides a step-by-step walkthrough for demonstrating distributed tracing capabilities using Zipkin with this microservices application.

## Prerequisites

- Application deployed and running (see [README.md](README.md))
- Zipkin UI accessible
- `curl` or similar HTTP client

## Setup: Get Your Service URLs

```bash
# Get service URLs from OpenShift/Kubernetes Routes
export FRONTEND_URL=$(kubectl get route frontend -n tracing-demo -o jsonpath='{.spec.host}')
export ZIPKIN_URL=$(kubectl get route zipkin -n tracing-demo -o jsonpath='{.spec.host}')

echo "Frontend: http://${FRONTEND_URL}"
echo "Zipkin UI: http://${ZIPKIN_URL}"
```

---

## Demo Flow 1: End-to-End Trace

**Goal**: Show a clean, successful distributed trace across all services

### 1. Generate Traffic Across All Service Paths

```bash
# Browse the catalog - frontend → catalog
curl http://${FRONTEND_URL}/products

# Add an item to cart - frontend → cart → catalog (cart validates product exists)
curl -X POST http://${FRONTEND_URL}/cart/user123/items \
  -H "Content-Type: application/json" \
  -d '{"product_id":"1","quantity":2}'

# Trigger checkout - deepest call chain: frontend → checkout → inventory + payment
curl -X POST http://${FRONTEND_URL}/checkout \
  -H "Content-Type: application/json" \
  -d '{"user_id":"user123"}'
```

### 2. Open Zipkin UI

Navigate to: `http://${ZIPKIN_URL}`

### 3. Find the Checkout Trace

1. Click **"Find Traces"**
2. Select service: **frontend**
3. Set limit to **10**
4. Click **"RUN QUERY"**
5. Click the **most recent trace** (usually the longest duration)

### 4. Walk Through the Waterfall View

**Key Points to Highlight:**

- **Same Trace ID**: Note the trace ID at the top appears in every single span
  - *"This is the thread connecting all 5 services - one request, one ID"*

- **Waterfall View** (left to right):
  - Each row = one service
  - Bars show relative time
  - Nested bars = child calls
  - Click any span to show tags (HTTP method, status code, URL)

- **Service Call Chain**:
  ```
  frontend (80ms total)
    └─> checkout (60ms)
        ├─> cart (15ms)
        │   └─> catalog (5ms)
        ├─> inventory (20ms)
        └─> payment (15ms)
  ```

**Demo Script**:
> "See how one user request flows through 5 different services? The trace ID stays the same across all of them. That's the magic of distributed tracing. Without this, we'd be correlating timestamps across 5 different log files."

---

## Demo Flow 2: Injected Latency - Finding a Slow Service

**Goal**: Show how to identify performance bottlenecks using trace timing

### 1. Enable Contention Simulation on Inventory

```bash
# Enable inventory contention (simulates database lock or slow query)
curl -X POST http://${FRONTEND_URL}/inventory/admin/config \
  -H "Content-Type: application/json" \
  -d '{"contention_rate":1.0}'
```

> **Note**: If the endpoint differs, check your inventory service code for the admin configuration endpoint.

### 2. Fire the Same Checkout Request

```bash
curl -X POST http://${FRONTEND_URL}/checkout \
  -H "Content-Type: application/json" \
  -d '{"user_id":"demo-user"}'
```

### 3. Open Zipkin - Sort by Duration

1. Go to Zipkin UI
2. Search for **frontend** service
3. Sort traces by **duration (descending)**
4. Click the new trace (noticeably longer - ~800ms vs ~40ms before)

### 4. Point to the Inventory Span

**Key Points to Highlight:**

- The **inventory span dominates the waterfall** - it's the widest bar
- Click the inventory span and show the tags
- You may see a `contention` or `lock` annotation

**Demo Script**:
> "See how this trace took 800ms vs 40ms before? Let's find out why. Look at the waterfall - inventory is the culprit. Not frontend. Not checkout. Inventory. We knew that in 10 seconds, not 10 minutes of log diving."

### 5. Disable Contention and Show Recovery

```bash
# Disable contention
curl -X POST http://${FRONTEND_URL}/inventory/admin/config \
  -H "Content-Type: application/json" \
  -d '{"contention_rate":0.0}'

# Run another checkout
curl -X POST http://${FRONTEND_URL}/checkout \
  -H "Content-Type: application/json" \
  -d '{"user_id":"demo-user"}'
```

**Demo Script**:
> "Now watch what happens when we fix it. The trace returns to normal. The before/after comparison in Zipkin is very compelling."

---

## Demo Flow 3: Error Propagation - Where Did It Fail?

**Goal**: Show how errors in one service surface in the trace with full context

### 1. Enable Fault Injection on Payment

```bash
# Enable payment failures (100% failure rate for clean demo)
curl -X POST http://${FRONTEND_URL}/payment/admin/config \
  -H "Content-Type: application/json" \
  -d '{"failure_rate":1.0,"latency_ms":0}'
```

### 2. Fire a Checkout Request - It Will Fail

```bash
curl -X POST http://${FRONTEND_URL}/checkout \
  -H "Content-Type: application/json" \
  -d '{"user_id":"demo-user"}' \
  -w "\nHTTP %{http_code}\n"
```

The `-w` flag prints the HTTP status code so the audience can see the error response (likely 500 or 502).

### 3. Open Zipkin - Traces with Errors Show in Red

1. Filter by **frontend** service
2. The failed trace appears with a **red indicator**
3. Click it

**Demo Script**:
> "Zipkin marks errored traces automatically. See the red indicator? That's our failed request."

### 4. Click the Red Payment Span - Show Tags

Expand **tags/annotations**:
- `http.status_code`: 500
- `error`: true
- `error.message`: "Payment processing failed"
- Timestamp of the exact failure

**Demo Script**:
> "Payment failed. We know the service, the HTTP status, the error message, the exact timestamp. All captured automatically by OpenTelemetry instrumentation. Nobody had to add logging code."

### 5. Disable Fault and Show Recovery

```bash
# Disable payment failures
curl -X POST http://${FRONTEND_URL}/payment/admin/config \
  -H "Content-Type: application/json" \
  -d '{"failure_rate":0.0,"latency_ms":50}'

# Fire another checkout
curl -X POST http://${FRONTEND_URL}/checkout \
  -H "Content-Type: application/json" \
  -d '{"user_id":"demo-user"}'
```

**Demo Script**:
> "Now it's fixed. The contrast between the red error trace and the clean one is very visual."

---

## Demo Flow 4: Dependency Graph

**Goal**: Show the big picture of your architecture built from real traffic

### 1. Generate a Burst of Traffic Across All Paths

Run this loop ~30 seconds before the demo to populate the dependency graph:

```bash
for i in $(seq 1 20); do
  curl -s http://${FRONTEND_URL}/products > /dev/null
  curl -s -X POST http://${FRONTEND_URL}/cart/user123/items \
    -H "Content-Type: application/json" \
    -d '{"product_id":"1","quantity":1}' > /dev/null
  curl -s -X POST http://${FRONTEND_URL}/checkout \
    -H "Content-Type: application/json" \
    -d '{"user_id":"demo-user"}' > /dev/null
  sleep 0.5
done
```

### 2. Open Zipkin > Dependencies Tab

1. Navigate to **Dependencies** tab
2. Set time range to **"Last 1 hour"**
3. The service graph appears with call counts on the edges

**Demo Script**:
> "Every arrow here represents real calls that happened. The graph built itself from production traffic. No configuration files, no manual mapping."

### 3. Hover Over Each Node to Show Call Counts

Zipkin shows call volume per edge. Point out interesting dependencies:

- **cart → catalog**: A back-call that might not be obvious from code review
- **checkout → inventory + payment**: Parallel calls for efficiency

**Demo Script**:
> "Notice cart calls catalog - that's a dependency you might not catch in a code review, but it shows up here immediately in production traffic."

### 4. Click a Node to Filter Traces for That Service

Show how the dependency graph links back to individual traces:

1. Click the **payment** node
2. Zipkin filters to show only traces involving payment
3. Click a trace to drill into the details

**Demo Script**:
> "You can drill from the map to the specific trace. From architecture view to request details in two clicks."

---

## Advanced Demo Scenarios

### Scenario A: Comparing Before/After Performance

1. Run checkout with normal settings, note the duration
2. Enable inventory contention
3. Run checkout again, show the increased duration
4. Open both traces side-by-side in separate browser tabs
5. Compare the waterfall views

### Scenario B: Cascading Failures

1. Enable payment failures (50% rate)
2. Generate 10 checkout requests
3. Show in Zipkin how some succeed (green) and some fail (red)
4. Click a failed trace and show how the error propagated from payment → checkout → frontend

### Scenario C: Service Mesh Integration

If deployed with Consul Service Mesh:

1. Show the dual-span pattern (Envoy ingress + application span)
2. Explain how mTLS adds minimal overhead (visible in Envoy span timing)
3. Show service-to-service authorization in action

---

## Troubleshooting Demo Issues

### No Traces Appearing

```bash
# Check if Zipkin is receiving spans
curl http://${ZIPKIN_URL}/api/v2/services

# Verify application is sending traces
kubectl logs -n tracing-demo deployment/frontend --tail=50 | grep -i zipkin
```

### Traces Missing Services

- Ensure all services have `ZIPKIN_URL` environment variable set
- Check service logs for connection errors
- Verify network connectivity between services and Zipkin

### Admin Endpoints Not Working

Check the actual admin endpoint paths in your service code:
- `cmd/inventory/main.go` - Look for admin routes
- `cmd/payment/main.go` - Look for config endpoints

---

## Demo Tips

1. **Pre-populate the dependency graph** before the demo (run the traffic generation loop)
2. **Keep Zipkin UI open in a separate window** for quick switching
3. **Use the browser's zoom** to make traces more visible to the audience
4. **Practice the timing** - some operations take a few seconds to appear in Zipkin
5. **Have a backup plan** - if live demo fails, have screenshots ready

---

## Quick Reference: Service Endpoints

| Service   | Port | Key Endpoints                          |
|-----------|------|----------------------------------------|
| frontend  | 8080 | `/products`, `/cart/:user/items`, `/checkout` |
| catalog   | 8081 | `/products`, `/products/:id`           |
| cart      | 8082 | `/cart/:user`, `/cart/:user/items`     |
| checkout  | 8083 | `/checkout`                            |
| payment   | 8084 | `/payment/process`, `/admin/config`    |
| inventory | 8085 | `/inventory/reserve`, `/admin/config`  |
| zipkin    | 9411 | `/api/v2/spans` (collector)            |

---

## Additional Resources

- [README.md](README.md) - Full deployment and configuration guide
- [loadtest/README.md](loadtest/README.md) - Load testing tools and scenarios
- [Zipkin Documentation](https://zipkin.io/pages/quickstart.html)
- [OpenTelemetry Go](https://opentelemetry.io/docs/instrumentation/go/)