#!/usr/bin/env bash
# Fix datasource UIDs + align dashboard variables with Consul (Service.Namespace / Service.Name).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OBS_NS="${OBS_NS:-observability}"
DASHBOARD_CM="${DASHBOARD_CM:-consul-data-plane-performance}"
DASHBOARD_KEY="${DASHBOARD_KEY:-consul-data-plane-performance.json}"
GRAFANA_DS_NAME="${GRAFANA_DS_NAME:-prometheus-standalone}"

NEW_UID=$(kubectl get grafanadatasource "$GRAFANA_DS_NAME" -n "$OBS_NS" -o jsonpath='{.status.uid}')
if [[ -z "$NEW_UID" ]]; then
  echo "ERROR: GrafanaDatasource $GRAFANA_DS_NAME has no status.uid."
  exit 1
fi

echo "Prometheus datasource UID: $NEW_UID"

BACKUP="/tmp/${DASHBOARD_CM}-backup-$(date +%Y%m%d-%H%M%S).json"
kubectl get configmap "$DASHBOARD_CM" -n "$OBS_NS" -o json > "$BACKUP"
echo "Backup: $BACKUP"

TMP_JSON=$(mktemp)
kubectl get configmap "$DASHBOARD_CM" -n "$OBS_NS" -o json | \
  jq -r --arg key "$DASHBOARD_KEY" '.data[$key]' > "$TMP_JSON"

sed -i.bak \
  -e "s/8ddbb987-80a8-4572-aa17-66c65601cd9b/${NEW_UID}/g" \
  -e "s/558b3887-3848-4b72-a6f7-083651b7eb89/${NEW_UID}/g" \
  "$TMP_JSON"
rm -f "${TMP_JSON}.bak"

if [[ ! -s "$TMP_JSON" ]]; then
  echo "ERROR: Dashboard JSON in ConfigMap is empty. Restore a backup, e.g.:"
  echo "  kubectl apply -f /tmp/consul-data-plane-performance-backup-YYYYMMDD-HHMMSS.json"
  exit 1
fi

UPDATED=$(mktemp)
python3 "$SCRIPT_DIR/patch-dashboard-consul-vars.py" < "$TMP_JSON" > "$UPDATED"

# ConfigMap .data values must be strings; do not use --rawfile (corrupts JSON).
# Replace ConfigMap in one shot (avoid apply conflicts on large JSON).
kubectl delete configmap "$DASHBOARD_CM" -n "$OBS_NS" --ignore-not-found
kubectl create configmap "$DASHBOARD_CM" -n "$OBS_NS" --from-file="${DASHBOARD_KEY}=${UPDATED}"

kubectl annotate grafanadashboard consul-data-plane-performance -n "$OBS_NS" \
  "resync-requested=$(date +%s)" --overwrite 2>/dev/null || true

rm -f "$TMP_JSON" "$UPDATED"

echo ""
echo "Dashboard updated for Consul variables:"
echo "  var-namespace  -> consul_source_namespace (Consul Service.Namespace)"
echo "  var-service    -> consul_source_service (Consul Service.Name)"
echo ""
echo "Apply Consul Helm URL template with Helm-escaped {{ }} placeholders:"
echo "  helm upgrade consul hashicorp/consul -n consul -f deploy/observability/consul-values-observability.yaml"
