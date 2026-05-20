#!/bin/bash
# Diagnostic script to troubleshoot Consul topology graph issues

set -u

NAMESPACE="tracing-demo"
CONSUL_NAMESPACE="consul"

echo "=========================================="
echo "Consul Topology Graph Diagnostics"
echo "=========================================="
echo ""

# Check 1: Verify pods are running with sidecars
echo "1. Checking pod status (should show 2/2 Ready)..."
echo ""
kubectl get pods -n $NAMESPACE
echo ""

# Check 2: Verify Consul annotations on pods
echo "2. Checking Consul annotations on frontend pod..."
echo ""
FRONTEND_POD=$(kubectl get pod -n $NAMESPACE -l app.kubernetes.io/name=frontend -o jsonpath='{.items[0].metadata.name}')
echo "Pod: $FRONTEND_POD"
echo ""
echo "Annotations:"
kubectl get pod $FRONTEND_POD -n $NAMESPACE -o jsonpath='{.metadata.annotations}' | jq '.'
echo ""

# Check 3: Verify connect-service-upstreams annotation specifically
echo "3. Checking connect-service-upstreams annotation..."
echo ""
echo "Frontend upstreams:"
kubectl get pod -n $NAMESPACE -l app.kubernetes.io/name=frontend -o jsonpath='{.items[0].metadata.annotations.consul\.hashicorp\.com/connect-service-upstreams}' || echo "NOT FOUND"
echo ""
echo ""
echo "Cart upstreams:"
kubectl get pod -n $NAMESPACE -l app.kubernetes.io/name=cart -o jsonpath='{.items[0].metadata.annotations.consul\.hashicorp\.com/connect-service-upstreams}' || echo "NOT FOUND"
echo ""
echo ""
echo "Checkout upstreams:"
kubectl get pod -n $NAMESPACE -l app.kubernetes.io/name=checkout -o jsonpath='{.items[0].metadata.annotations.consul\.hashicorp\.com/connect-service-upstreams}' || echo "NOT FOUND"
echo ""
echo ""

# Check 4: Verify services are registered in Consul
echo "4. Checking Consul service registration..."
echo ""
CONSUL_POD=$(kubectl get pod -n $CONSUL_NAMESPACE -l component=server -o jsonpath='{.items[0].metadata.name}')
echo "Consul server pod: $CONSUL_POD"
echo ""
echo "Registered services:"
kubectl exec $CONSUL_POD -n $CONSUL_NAMESPACE -- consul catalog services || echo "Could not list Consul services"
echo ""

# Check 5: Check service details in Consul
echo "5. Checking frontend service details in Consul..."
echo ""
kubectl exec $CONSUL_POD -n $CONSUL_NAMESPACE -- consul catalog nodes -service frontend || echo "Could not query frontend service nodes"
echo ""

# Check 6: Check for service-defaults config
echo "6. Checking for service-defaults configuration..."
echo ""
kubectl exec $CONSUL_POD -n $CONSUL_NAMESPACE -- consul config list -kind service-defaults || echo "No service-defaults found"
echo ""

# Check 7: Check Consul version and edition
echo "7. Checking Consul version and edition..."
echo ""
kubectl exec $CONSUL_POD -n $CONSUL_NAMESPACE -- consul version || echo "Could not retrieve Consul version"
echo ""

# Check 8: Check if UI config is enabled
echo "8. Checking Consul UI configuration..."
echo ""
kubectl exec $CONSUL_POD -n $CONSUL_NAMESPACE -- consul info | grep -i ui || echo "UI info not found"
echo ""

# Check 9: Look for any Consul Connect errors in logs
echo "9. Checking for Consul Connect errors in frontend pod logs..."
echo ""
kubectl logs $FRONTEND_POD -n $NAMESPACE -c consul-connect-inject-init --tail=20 2>/dev/null || echo "No init container logs"
echo ""
kubectl logs $FRONTEND_POD -n $NAMESPACE -c consul-dataplane --tail=20 2>/dev/null || echo "No dataplane logs"
echo ""

# Check 10: Verify Helm values
echo "10. Checking current Helm values for consulUpstreams..."
echo ""
helm get values zipkin-demo -n $NAMESPACE | grep -A 20 "services:" || echo "Could not retrieve Helm values"
echo ""

echo "=========================================="
echo "Diagnostic Summary"
echo "=========================================="
echo ""
echo "Common issues and solutions:"
echo ""
echo "1. If annotations are missing:"
echo "   - Run: helm upgrade zipkin-demo ./charts/zipkin-otel-microdemo -n tracing-demo --reuse-values"
echo "   - Then: kubectl rollout restart deployment -n tracing-demo"
echo ""
echo "2. If using Consul Community Edition:"
echo "   - Topology view requires Consul Enterprise"
echo "   - Check: kubectl exec $CONSUL_POD -n consul -- consul version"
echo ""
echo "3. If services not registered:"
echo "   - Check Consul Connect injection is working"
echo "   - Verify pods have 2/2 containers (app + sidecar)"
echo ""
echo "4. If upstreams annotation is present but topology empty:"
echo "   - Wait 1-2 minutes for Consul to sync"
echo "   - Generate some traffic: cd loadtest && ./simple-load.sh"
echo "   - Check Consul UI metrics are enabled"
echo ""

# Made with Bob
