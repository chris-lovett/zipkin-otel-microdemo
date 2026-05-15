# Observability consolidation (standalone Prometheus + Consul mesh)

Use **standalone Prometheus** in `observability` to scrape **Envoy/consul-dataplane** metrics on port **20200**. Do not use per-pod Prometheus sidecars or OpenShift user-workload ServiceMonitors for this demo.

## Prerequisites

- Consul Helm release with mesh metrics on `0.0.0.0:20200` (see `consul-values-observability.yaml`)
- Namespace `observability` exists
- App deployed from `charts/zipkin-otel-microdemo` (no prometheus-sidecar)

## 1. Upgrade Consul (cluster-wide metrics)

```bash
helm upgrade consul hashicorp/consul -n consul \
  -f deploy/observability/consul-values-observability.yaml
```

Merge with your existing `-f` values file if you have one.

## 2. Upgrade standalone Prometheus

`prometheus-values.yaml` uses `existingClaim: prometheus-server` so Helm does not try to resize or change the StorageClass on an existing PVC.

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm upgrade --install prometheus prometheus-community/prometheus \
  -n observability \
  -f deploy/observability/prometheus-values.yaml
```

Fresh install (no existing PVC): remove `existingClaim` from `server.persistentVolume` and set `size` / `storageClass` to match your cluster (e.g. `20Gi`, `gp3-csi` on ROSA).

Verify targets:

```bash
kubectl port-forward -n observability svc/prometheus-server 9090:80
# http://localhost:9090/targets — look for job consul-mesh-envoy, namespace tracing-demo, port 20200
```

## 3. Redeploy the demo (no sidecar)

```bash
helm upgrade --install zipkin-demo ./charts/zipkin-otel-microdemo -n tracing-demo
kubectl rollout status deployment -n tracing-demo --timeout=5m
```

Pods should be **2/2** Ready (app + consul-dataplane), not 3/3.

## 4. Remove OpenShift user-workload scrape path (optional)

```bash
kubectl delete servicemonitor consul-mesh-metrics -n tracing-demo --ignore-not-found
kubectl delete configmap prometheus-sidecar-config -n tracing-demo --ignore-not-found
kubectl label namespace tracing-demo openshift.io/user-monitoring- 2>/dev/null || true
```

## 5. Grafana datasource

```bash
kubectl apply -f deploy/observability/grafana-datasource.yaml
kubectl delete grafanadatasource prometheus-thanos -n observability --ignore-not-found

# Fix dashboard panels still pointing at deleted Thanos UID + URL param mismatch
chmod +x deploy/observability/fix-grafana-dashboard.sh
./deploy/observability/fix-grafana-dashboard.sh

# Remove stale consul-mesh-metrics Service from topology
./deploy/observability/cleanup-mesh-metrics-svc.sh
```

**Consul “Open dashboard”:** Use Helm-escaped templates in `consul-values-observability.yaml` so Consul substitutes `Service.Name` / `Service.Namespace` (not literal `{{Service.Name}}` in the browser). Run `./fix-grafana-dashboard.sh` so Grafana queries `consul_source_service` / `consul_source_namespace` — the same labels Consul uses for metrics.

## 6. NetworkPolicy (if needed)

If scrape from `observability` fails after applying egress policies in `tracing-demo`:

```bash
kubectl apply -f deploy/observability/networkpolicy-prometheus-scrape.yaml
```

## 7. Generate mesh metrics

```bash
cd loadtest && ./mesh-load.sh
```

Query in Prometheus:

```promql
count(envoy_cluster_upstream_rq_total{namespace="tracing-demo"})
```

## Verify scrape path

```bash
POD=$(kubectl get pod -n tracing-demo -l app.kubernetes.io/name=frontend -o jsonpath='{.items[0].metadata.name}')
IP=$(kubectl get pod -n tracing-demo "$POD" -o jsonpath='{.status.podIP}')

kubectl run curl-test -n observability --rm -i --restart=Never \
  --image=curlimages/curl \
  -- curl -sf --max-time 10 "http://${IP}:20200/metrics" | grep -E '^envoy_|^consul_dataplane' | head -5
```

Do **not** run this test from the `default` namespace (`default-deny-egress` blocks it).
