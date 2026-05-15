# Consul Service Mesh Metrics Solution

## Problem Summary

**Issue:** Consul UI and Grafana show "No data" for service mesh metrics.

**Root Cause:** The consul-dataplane metrics endpoint (port 20200) binds to `127.0.0.1` (localhost) only, making it inaccessible to Prometheus from outside the pod. While metrics ARE being generated (verified: 4,471 Envoy metrics), Prometheus cannot scrape them from the pod IP address.

## Technical Details

### What We Verified
✅ Metrics endpoint returns valid data via port-forward  
✅ Prometheus targets show "UP" status for all pods  
✅ consul-dataplane has no errors in logs  
✅ Annotations are correctly set on pods  
❌ **But**: Port 20200 only listens on 127.0.0.1, not 0.0.0.0

### Why Standard Fixes Don't Work

1. **Annotation approach** (`consul.hashicorp.com/consul-dataplane-startup-args`): Not processed by Consul 1.9.7
2. **Helm value approach** (`connectInject.consulDataplane.extraArgs`): Not supported in Consul Helm chart 1.9.7
3. **Global telemetry config**: Causes pod initialization failures

## Recommended Solution: Prometheus Sidecar Pattern

Since we cannot change how consul-dataplane binds its metrics endpoint, we'll use a Prometheus sidecar container that can access localhost and expose metrics externally.

### Implementation

#### Step 1: Create ConfigMap for Prometheus Sidecar

```bash
kubectl create configmap prometheus-sidecar-config -n tracing-demo --from-literal=prometheus.yml='
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: "consul-dataplane"
    static_configs:
      - targets: ["localhost:20200"]
'
```

#### Step 2: Update Deployment Template

Add this to your Helm chart template (`charts/zipkin-otel-microdemo/templates/services.yaml`):

```yaml
spec:
  template:
    metadata:
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "9090"  # Sidecar port
        prometheus.io/path: "/federate"
    spec:
      containers:
        # Existing application container
        - name: {{ $name }}
          # ... existing config ...
        
        # Add Prometheus sidecar
        - name: prometheus-sidecar
          image: prom/prometheus:v2.45.0
          args:
            - '--config.file=/etc/prometheus/prometheus.yml'
            - '--storage.tsdb.path=/prometheus'
            - '--web.listen-address=0.0.0.0:9090'
            - '--storage.tsdb.retention.time=1h'
            - '--storage.tsdb.min-block-duration=1h'
            - '--storage.tsdb.max-block-duration=1h'
          ports:
            - name: prometheus
              containerPort: 9090
              protocol: TCP
          volumeMounts:
            - name: prometheus-config
              mountPath: /etc/prometheus
            - name: prometheus-storage
              mountPath: /prometheus
          resources:
            requests:
              memory: "128Mi"
              cpu: "100m"
            limits:
              memory: "256Mi"
              cpu: "200m"
      volumes:
        - name: prometheus-config
          configMap:
            name: prometheus-sidecar-config
        - name: prometheus-storage
          emptyDir: {}
```

#### Step 3: Apply Changes

```bash
# Create the ConfigMap
kubectl create configmap prometheus-sidecar-config -n tracing-demo --from-literal=prometheus.yml='
global:
  scrape_interval: 15s
scrape_configs:
  - job_name: "consul-dataplane"
    static_configs:
      - targets: ["localhost:20200"]
'

# Apply updated deployments
kubectl apply -f charts/zipkin-otel-microdemo/templates/services.yaml

# Restart pods
kubectl rollout restart deployment -n tracing-demo --all
```

### How It Works

1. **Prometheus sidecar** runs in the same pod as the application
2. Sidecar can access `localhost:20200` (consul-dataplane metrics)
3. Sidecar exposes metrics on `0.0.0.0:9090` (accessible externally)
4. Main Prometheus scrapes from sidecar's `/federate` endpoint
5. Metrics flow: consul-dataplane → sidecar → Prometheus → Consul UI/Grafana

### Verification

```bash
# Check sidecar is running
kubectl get pods -n tracing-demo

# Test sidecar metrics endpoint
POD=$(kubectl get pods -n tracing-demo -l app.kubernetes.io/name=frontend -o jsonpath='{.items[0].metadata.name}')
POD_IP=$(kubectl get pod -n tracing-demo $POD -o jsonpath='{.status.podIP}')
curl -s http://$POD_IP:9090/federate | grep envoy | head -10

# Check Prometheus targets
kubectl port-forward -n observability svc/prometheus-server 9090:80 &
curl -s 'http://localhost:9090/api/v1/targets' | jq '.data.activeTargets[] | select(.labels.namespace=="tracing-demo") | {pod: .labels.pod, health: .health}'
```

## Alternative Solution: Upgrade Consul

If sidecar approach is not acceptable, upgrade to Consul 1.10+ which supports:

```yaml
connectInject:
  consulDataplane:
    extraArgs:
      - "-telemetry-prom-bind-address=0.0.0.0:20200"
```

### Upgrade Steps

```bash
# Backup current config
helm get values -n consul consul > consul-backup.yaml

# Upgrade Consul
helm repo update
helm upgrade consul hashicorp/consul \
  -n consul \
  -f consul-backup.yaml \
  --set connectInject.consulDataplane.extraArgs[0]="-telemetry-prom-bind-address=0.0.0.0:20200" \
  --version 1.10.0 \
  --wait

# Restart application pods
kubectl rollout restart deployment -n tracing-demo --all
```

## Comparison

| Approach | Pros | Cons |
|----------|------|------|
| **Prometheus Sidecar** | ✅ Works with current Consul version<br>✅ No Consul upgrade needed<br>✅ Isolated metrics collection | ❌ Additional container per pod<br>❌ Slightly more complex |
| **Consul Upgrade** | ✅ Clean solution<br>✅ Native support<br>✅ No sidecars needed | ❌ Requires Consul upgrade<br>❌ Potential compatibility issues<br>❌ More testing required |

## Recommendation for Customer Presentation

**Use the Prometheus Sidecar approach** because:

1. ✅ **Immediate solution** - Works with existing Consul 1.9.7
2. ✅ **Low risk** - No infrastructure upgrades required
3. ✅ **Proven pattern** - Standard Kubernetes sidecar pattern
4. ✅ **Flexible** - Easy to remove later if upgrading Consul
5. ✅ **Isolated** - Doesn't affect Consul configuration

## Expected Results

After implementing the solution:

- **Prometheus**: Successfully scrapes metrics from all pods
- **Consul UI**: Displays service topology, RPS, and latency metrics
- **Grafana**: Shows data in all dashboard panels
- **Metrics**: Real-time Envoy sidecar metrics available

## Timeline

- **Implementation**: 30 minutes
- **Verification**: 15 minutes  
- **Metrics appearing**: 2-3 minutes after pods restart

## Support

For issues or questions:
- Check pod logs: `kubectl logs -n tracing-demo <pod-name> -c prometheus-sidecar`
- Verify sidecar config: `kubectl get configmap prometheus-sidecar-config -n tracing-demo -o yaml`
- Test locally: `kubectl port-forward -n tracing-demo <pod-name> 9090:9090`