# Consul Server Metrics - Complete Solution

## Problem Summary

The **Consul Servers dashboard shows "No data"** because:

1. ❌ Consul server metrics endpoint requires ACL authentication
2. ❌ Prometheus is scraping without providing the ACL token → `403 Forbidden`
3. ❌ No Prometheus Operator (using standalone Prometheus)
4. ❌ ServiceMonitor approach won't work without Prometheus Operator

## Root Cause

- Consul has ACLs enabled (`manageSystemACLs: true`)
- The `/v1/agent/metrics` endpoint requires authentication
- Standalone Prometheus uses pod annotations but can't inject bearer tokens
- Current scrape attempts fail with HTTP 403

## Solution: Add Consul-Specific Scrape Config

Since this deployment uses **standalone Prometheus** (not Prometheus Operator), we need to:

1. Mount the Consul ACL token secret into Prometheus pod
2. Add a dedicated scrape config for Consul servers with bearer token authentication

### Step 1: Mount ACL Token Secret

Edit the Prometheus Helm values or deployment to mount the secret:

```yaml
# In prometheus values.yaml or deployment
server:
  extraSecretMounts:
    - name: consul-acl-token
      secretName: consul-bootstrap-acl-token
      mountPath: /var/run/secrets/consul-acl-token
      readOnly: true
```

### Step 2: Add Scrape Configuration

Add this to the Prometheus ConfigMap under `scrape_configs`:

```yaml
    - job_name: 'consul-servers'
      honor_labels: true
      kubernetes_sd_configs:
      - role: pod
        namespaces:
          names:
          - consul
      # Use bearer token from mounted secret
      bearer_token_file: /var/run/secrets/consul-acl-token/token
      scheme: https
      tls_config:
        insecure_skip_verify: true
      relabel_configs:
      # Only scrape pods with component=server label
      - source_labels: [__meta_kubernetes_pod_label_component]
        action: keep
        regex: server
      - source_labels: [__meta_kubernetes_pod_label_app]
        action: keep
        regex: consul
      # Set metrics path
      - source_labels: []
        target_label: __metrics_path__
        replacement: /v1/agent/metrics
      # Add format=prometheus query parameter
      - source_labels: [__address__]
        target_label: __param_format
        replacement: prometheus
      # Use port 8501 (HTTPS)
      - source_labels: [__address__]
        regex: ([^:]+)(?::\d+)?
        replacement: ${1}:8501
        target_label: __address__
      # Add labels
      - source_labels: [__meta_kubernetes_pod_name]
        target_label: pod
      - source_labels: [__meta_kubernetes_namespace]
        target_label: namespace
      - source_labels: [__meta_kubernetes_pod_label_datacenter]
        target_label: datacenter
      - source_labels: [__meta_kubernetes_pod_label_component]
        target_label: component
```

### Step 3: Apply Changes

```bash
# 1. Update Prometheus Helm values with extraSecretMounts
helm upgrade prometheus prometheus-community/prometheus \
  -n observability \
  -f prometheus-values.yaml

# 2. Verify secret is mounted
kubectl exec -n observability prometheus-server-xxx -- ls -la /var/run/secrets/consul-acl-token/

# 3. Verify Prometheus reloaded config
kubectl logs -n observability prometheus-server-xxx -c prometheus-server | grep "Completed loading of configuration file"
```

## Verification

```bash
# 1. Check Prometheus targets
kubectl port-forward -n observability svc/prometheus-server 9090:80
# Visit http://localhost:9090/targets
# Look for "consul-servers" job with status "UP"

# 2. Query metrics
# Visit http://localhost:9090/graph
# Query: consul_raft_applied_index
# Query: consul_autopilot_healthy
# Query: consul_members_servers

# 3. Check Grafana dashboard
# Open "Consul Servers" dashboard
# Select datacenter and pod
# Verify panels show data
```

## Expected Metrics

Once configured, you should see:

```
consul_autopilot_healthy
consul_raft_applied_index
consul_raft_last_index
consul_raft_commitTime_sum
consul_raft_commitTime_count
consul_raft_leader_lastContact
consul_client_rpc
consul_members_servers
consul_members_clients
consul_state_service_instances
consul_runtime_alloc_bytes
consul_runtime_sys_bytes
consul_runtime_num_goroutines
```

## Alternative: Use Telemetry Collector

If you don't want to modify Prometheus configuration, you can use the Consul Telemetry Collector as a proxy:

```bash
# Check if telemetry collector is running
kubectl get pod -n consul -l app=consul,component=telemetry-collector

# Port-forward to test
kubectl port-forward -n consul svc/consul-telemetry-collector 9090:9090
curl http://localhost:9090/metrics | grep consul_

# If working, configure Prometheus to scrape the telemetry collector instead
```

## Files Created

- [`consul-server-servicemonitor.yaml`](consul-server-servicemonitor.yaml) - ServiceMonitor (for Prometheus Operator, not applicable here)
- [`prometheus-consul-scrape-config.yaml`](prometheus-consul-scrape-config.yaml) - Scrape config to add to Prometheus
- This document - Complete solution guide

## Current Status

✅ Consul server is running and healthy
✅ Metrics endpoint is accessible with ACL token
✅ Metrics configuration is enabled in Consul
⚠️ Prometheus needs to be configured to use ACL token
⚠️ Helm release shows "failed" status (cosmetic issue, Consul is working)

## Next Steps

1. **Update Prometheus Helm values** to mount the ACL token secret
2. **Add the scrape config** to Prometheus ConfigMap
3. **Restart Prometheus** to apply changes
4. **Verify metrics** are being scraped
5. **Check Grafana dashboard** shows data

## Troubleshooting

### Metrics still showing 403

```bash
# Verify token is mounted
kubectl exec -n observability prometheus-server-xxx -- cat /var/run/secrets/consul-acl-token/token

# Test token manually
TOKEN=$(kubectl get secret consul-bootstrap-acl-token -n consul -o jsonpath='{.data.token}' | base64 -d)
kubectl exec consul-server-0 -n consul -- wget -qO- --no-check-certificate \
  --header="X-Consul-Token: $TOKEN" \
  "https://localhost:8501/v1/agent/metrics?format=prometheus" | head -20
```

### Prometheus not picking up config

```bash
# Check Prometheus logs
kubectl logs -n observability prometheus-server-xxx -c prometheus-server --tail=50

# Reload config
kubectl exec -n observability prometheus-server-xxx -c prometheus-server -- \
  wget --post-data='' http://localhost:9090/-/reload
```

### Dashboard still shows "No data"

```bash
# Verify metrics exist in Prometheus
kubectl port-forward -n observability svc/prometheus-server 9090:80
# Visit http://localhost:9090/graph
# Query: consul_raft_applied_index{job="consul-servers"}

# Check dashboard datasource UID
kubectl get grafanadatasource prometheus -n observability -o jsonpath='{.status.uid}'

# Verify dashboard uses correct UID
kubectl get configmap consul-servers-dashboard -n observability -o yaml | grep uid
```

## References

- [Consul Telemetry](https://developer.hashicorp.com/consul/docs/agent/telemetry)
- [Prometheus Configuration](https://prometheus.io/docs/prometheus/latest/configuration/configuration/)
- [Kubernetes SD Config](https://prometheus.io/docs/prometheus/latest/configuration/configuration/#kubernetes_sd_config)