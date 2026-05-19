# API Gateway Load Testing and Dashboard Verification

## Continuous Load Generator

A continuous load generator is running to populate the Gateway Health dashboard with realistic traffic patterns.

### Load Pattern

The generator creates:
- **70%** product list requests (`/products`)
- **20%** product detail requests (`/products/1`)
- **10%** cart operations (`/cart/user123`)
- **~5 requests/second** average rate

### Managing the Load Generator

**Check if running:**
```bash
ps aux | grep continuous-load.sh
# or
cat /tmp/load-generator.pid
```

**View logs:**
```bash
tail -f /tmp/load-generator.log
```

**Stop the load generator:**
```bash
# Using the PID file
kill $(cat /tmp/load-generator.pid)

# Or find and kill the process
pkill -f continuous-load.sh
```

**Restart the load generator:**
```bash
cd /Users/chrislovett/hashi/monitoring/tracing/zipkin-otel-microdemo
nohup ./deploy/api-gateway/continuous-load.sh > /tmp/load-generator.log 2>&1 &
echo $! > /tmp/load-generator.pid
```

## Viewing the Dashboard

### Access Grafana

```bash
# Port-forward to Grafana
kubectl port-forward -n observability svc/grafana 3000:80

# Open browser to http://localhost:3000
# Navigate to Dashboards → Gateway Health
```

### Expected Dashboard Panels

With the load generator running, you should see data in these panels:

#### API Gateway Section
1. **API GW Request Rate** - Shows ~0.18-0.33 req/s
2. **API GW 5xx Error Rate** - Should show "No data" (all requests successful)
3. **API GW P99 Latency** - Response time percentiles (~9-10ms)
4. **API GW Active Downstream Connections** - Active connections (~5)

#### Detailed Metrics
5. **API GW Request Rate (RPS)** - Time series graph showing request rate over time
6. **API GW Error Rate by Status Class (%)** - Breakdown by 2xx, 3xx, 4xx, 5xx
7. **API GW Latency Percentiles (ms)** - P50, P95, P99 latency trends

#### Terminating Gateway Section
- Shows "No data" (this is for terminating gateway, not API gateway)

#### Mesh Gateway Section  
- Shows "No data" (this is for mesh gateway cross-DC traffic)

## Verifying Metrics in Prometheus

### Port-forward to Prometheus
```bash
kubectl port-forward -n observability svc/prometheus-server 9090:80
```

### Check Targets
Visit http://localhost:9090/targets and look for:
- Job: `consul-api-gateway`
- Status: UP
- Last Scrape: Recent timestamp

### Query Metrics

**Request Rate:**
```promql
sum(rate(envoy_http_downstream_rq_total{job="consul-api-gateway"}[5m]))
```

**Total Requests:**
```promql
sum(envoy_http_downstream_rq_total{job="consul-api-gateway"})
```

**Requests by Response Code:**
```promql
sum(envoy_http_downstream_rq_xx{job="consul-api-gateway"}) by (envoy_response_code_class)
```

**Active Connections:**
```promql
sum(envoy_http_downstream_cx_active{job="consul-api-gateway"})
```

**P99 Latency:**
```promql
histogram_quantile(0.99, sum(rate(envoy_http_downstream_rq_time_bucket{job="consul-api-gateway"}[5m])) by (le))
```

## Generating Error Traffic

To populate the error panels, you can generate 5xx errors by:

1. **Stopping the backend service temporarily:**
```bash
kubectl scale deployment frontend -n tracing-demo --replicas=0
# Generate traffic (will get 503 errors)
# Restore service
kubectl scale deployment frontend -n tracing-demo --replicas=1
```

2. **Using the payment service failure injection:**
```bash
# Configure payment service to fail 30% of requests
kubectl exec -n tracing-demo deployment/payment -- wget -qO- \
  --post-data='{"failure_rate":0.3,"latency_ms":50}' \
  --header='Content-Type: application/json' \
  http://localhost:8084/admin/config
```

## Troubleshooting

### No Data in Dashboard

1. **Check Prometheus target:**
   ```bash
   kubectl port-forward -n observability svc/prometheus-server 9090:80
   # Visit http://localhost:9090/targets
   # Look for consul-api-gateway job
   ```

2. **Verify API Gateway is running:**
   ```bash
   kubectl get pods -n tracing-demo -l component=api-gateway
   ```

3. **Check metrics endpoint:**
   ```bash
   POD=$(kubectl get pods -n tracing-demo -l component=api-gateway -o jsonpath='{.items[0].metadata.name}')
   kubectl exec -n tracing-demo $POD -- wget -qO- http://localhost:20200/metrics | grep envoy_http
   ```

4. **Verify load generator is running:**
   ```bash
   ps aux | grep continuous-load.sh
   tail -f /tmp/load-generator.log
   ```

### Dashboard Shows Old Data

- Refresh the dashboard (click refresh button or press Ctrl+R)
- Adjust time range to "Last 5 minutes" or "Last 15 minutes"
- Check that load generator is still running

### Metrics Delayed

- Prometheus scrapes every 30 seconds
- Allow 30-60 seconds for new metrics to appear
- Dashboard refresh interval may need adjustment

## Performance Testing

For more intensive load testing, use the k6 load testing tool:

```bash
cd loadtest
k6 run -e BASE_URL=http://api-gateway.tracing-demo.svc.cluster.local:8080 k6/script.js
```

Or use the Python load generator:

```bash
cd loadtest
./advanced-load.py --scenario mixed --users 10 --duration 300
```

## Cleanup

When done testing:

```bash
# Stop the load generator
kill $(cat /tmp/load-generator.pid)

# Remove PID file
rm /tmp/load-generator.pid

# Clean up logs
rm /tmp/load-generator.log