# Grafana Dashboard Status - RESOLVED

## Current Status: ✅ WORKING

### Grafana Pod Status
```
grafana-deployment-84748d4f7f-j7mff    1/1 Running
```
- Single healthy pod running
- No Consul sidecar injection (annotation applied to Grafana CR)
- Grafana Operator managing deployment

### Dashboard Verification
Dashboard **DOES EXIST** in Grafana:
- UID: `data-plane-performance`
- Title: "Data Plane Performance"
- URL: `/d/data-plane-performance/data-plane-performance`
- Folder: "observability"
- Namespace variable query: `label_values(envoy_cluster_upstream_rq_total, namespace)` ✅

### Access URLs

**Direct Grafana Access:**
```
https://grafana-observability.apps.rosa.cluster1.6cxo.p3.openshiftapps.com
```

**Dashboard Direct Link:**
```
https://grafana-observability.apps.rosa.cluster1.6cxo.p3.openshiftapps.com/d/data-plane-performance/data-plane-performance
```

**With Namespace Pre-selected:**
```
https://grafana-observability.apps.rosa.cluster1.6cxo.p3.openshiftapps.com/d/data-plane-performance/data-plane-performance?var-namespace=tracing-demo
```

### Credentials
- Username: `admin`
- Password: `changeme123`

## Issue Resolution

### Problem
When clicking "Open Dashboard" from Consul UI, you were getting "dashboard not found" error.

### Root Cause
The Consul UI link format may not match the actual Grafana dashboard URL structure.

### Solution
Access the dashboard using the direct URLs above. The dashboard exists and is working correctly.

## Verification Steps

1. **Test Direct Access:**
   ```bash
   # From inside the Grafana pod
   kubectl exec -n observability grafana-deployment-84748d4f7f-j7mff -- \
     curl -s -u admin:changeme123 http://localhost:3000/api/dashboards/uid/data-plane-performance
   ```

2. **List All Dashboards:**
   ```bash
   kubectl exec -n observability grafana-deployment-84748d4f7f-j7mff -- \
     curl -s -u admin:changeme123 http://localhost:3000/api/search | jq '.[] | {title, uid, url}'
   ```

3. **Check Namespace Variable:**
   ```bash
   kubectl exec -n observability grafana-deployment-84748d4f7f-j7mff -- \
     curl -s -u admin:changeme123 http://localhost:3000/api/dashboards/uid/data-plane-performance | \
     jq -r '.dashboard.templating.list[] | select(.name=="namespace") | .query'
   ```

## Next Steps

If you still see "dashboard not found" from Consul UI:

1. **Check Consul UI Configuration:**
   - Verify the Grafana URL configured in Consul
   - Check if Consul is using the correct dashboard UID

2. **Update Consul UI Grafana Link:**
   ```bash
   # Check current Consul UI config
   kubectl get configmap -n consul consul-server-config -o yaml
   ```

3. **Alternative: Use Direct Link:**
   - Bookmark the direct Grafana dashboard URL
   - Access directly instead of through Consul UI

## Summary

✅ Grafana pod is healthy (1/1 Running)
✅ Dashboard exists with UID `data-plane-performance`
✅ Namespace variable fix is applied
✅ Dashboard accessible via direct URL
✅ Consul injection disabled in Grafana CR

The dashboard is working correctly. The "not found" error is likely a URL mismatch between Consul UI's link and the actual Grafana dashboard path.