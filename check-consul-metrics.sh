#!/bin/bash
PROM_POD=$(kubectl get pod -n observability -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[0].metadata.name}')

echo "=== Checking Consul Server Metrics Scraping ==="
echo ""

echo "1. Checking for consul-servers job target:"
kubectl exec -n observability $PROM_POD -c prometheus-server -- wget -qO- 'http://localhost:9090/api/v1/targets' | jq -r '.data.activeTargets[] | select(.labels.job == "consul-servers") | {job: .labels.job, pod: .labels.pod, health: .health, scrapeUrl: .scrapeUrl}'
echo ""

echo "2. Testing consul_raft_applied_index metric:"
kubectl exec -n observability $PROM_POD -c prometheus-server -- wget -qO- 'http://localhost:9090/api/v1/query?query=consul_raft_applied_index' | jq -r '.data.result[] | "\(.metric.pod): \(.value[1])"'
echo ""

echo "3. Testing consul_autopilot_healthy metric:"
kubectl exec -n observability $PROM_POD -c prometheus-server -- wget -qO- 'http://localhost:9090/api/v1/query?query=consul_autopilot_healthy' | jq -r '.data.result[] | "\(.metric.pod): \(.value[1])"'
