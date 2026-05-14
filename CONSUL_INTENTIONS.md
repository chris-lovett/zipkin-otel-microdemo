# Consul Service Mesh Intentions and ACLs

## Why Traffic Works Without Intentions

You've discovered an important aspect of Consul Service Mesh: **traffic can flow even when the UI shows "Connection Denied" and no intentions are configured**. Here's why:

### Default ACL Policy: "allow"

Consul has a default ACL policy that determines what happens when no explicit intention exists:

```
default_policy = "allow"  # This is the default
```

With `default_policy = "allow"`:
- ✅ Traffic flows between all services by default
- ✅ mTLS encryption is still enforced
- ✅ Service mesh features (observability, routing) still work
- ⚠️ The UI shows "Connection Denied" as a **warning** that no explicit intention exists
- ⚠️ This is **not recommended for production** (security risk)

### What the UI Warning Means

When the Consul UI shows "Connection Denied" on a topology connection:
- It's indicating that **no explicit intention** has been defined
- It's **NOT** saying traffic is actually blocked (if default_policy = "allow")
- It's a **security recommendation** to create explicit intentions

### Checking Your Default Policy

To see your current default ACL policy:

```bash
# Check Consul server configuration
kubectl exec -it consul-server-0 -n consul -- consul info | grep -i acl

# Or check the Helm values used to deploy Consul
helm get values consul -n consul | grep -i acl
```

Look for:
```yaml
global:
  acls:
    manageSystemACLs: true
    defaultPolicy: "allow"  # or "deny"
```

## Production Best Practice: "deny" by Default

For production environments, you should use:

```yaml
global:
  acls:
    manageSystemACLs: true
    defaultPolicy: "deny"  # Secure by default
```

With `default_policy = "deny"`:
- ❌ Traffic is **blocked** unless an explicit intention allows it
- ✅ Zero-trust security model
- ✅ Explicit allow-list of service-to-service communication
- ✅ Better security posture

## Creating Intentions for Your Demo App

Even with `default_policy = "allow"`, it's good practice to create explicit intentions. Here's how:

### Option 1: Using Consul UI

1. Navigate to **Intentions** in the left menu
2. Click **Create**
3. Configure:
   - **Source Service**: frontend
   - **Destination Service**: catalog
   - **Action**: Allow
4. Click **Save**

Repeat for all service connections:
- frontend → catalog
- frontend → cart
- frontend → checkout
- cart → catalog
- checkout → cart
- checkout → inventory
- checkout → payment

### Option 2: Using kubectl (ServiceIntentions CRD)

Create a file `service-intentions.yaml`:

```yaml
---
apiVersion: consul.hashicorp.com/v1alpha1
kind: ServiceIntentions
metadata:
  name: frontend
  namespace: tracing-demo
spec:
  destination:
    name: frontend
  sources:
    - name: "*"
      action: allow
      description: "Allow all services to call frontend (entry point)"
---
apiVersion: consul.hashicorp.com/v1alpha1
kind: ServiceIntentions
metadata:
  name: catalog
  namespace: tracing-demo
spec:
  destination:
    name: catalog
  sources:
    - name: frontend
      action: allow
      description: "Allow frontend to browse catalog"
    - name: cart
      action: allow
      description: "Allow cart to check catalog inventory"
---
apiVersion: consul.hashicorp.com/v1alpha1
kind: ServiceIntentions
metadata:
  name: cart
  namespace: tracing-demo
spec:
  destination:
    name: cart
  sources:
    - name: frontend
      action: allow
      description: "Allow frontend to manage cart"
    - name: checkout
      action: allow
      description: "Allow checkout to read cart contents"
---
apiVersion: consul.hashicorp.com/v1alpha1
kind: ServiceIntentions
metadata:
  name: checkout
  namespace: tracing-demo
spec:
  destination:
    name: checkout
  sources:
    - name: frontend
      action: allow
      description: "Allow frontend to initiate checkout"
---
apiVersion: consul.hashicorp.com/v1alpha1
kind: ServiceIntentions
metadata:
  name: payment
  namespace: tracing-demo
spec:
  destination:
    name: payment
  sources:
    - name: checkout
      action: allow
      description: "Allow checkout to process payments"
---
apiVersion: consul.hashicorp.com/v1alpha1
kind: ServiceIntentions
metadata:
  name: inventory
  namespace: tracing-demo
spec:
  destination:
    name: inventory
  sources:
    - name: checkout
      action: allow
      description: "Allow checkout to reserve inventory"
---
apiVersion: consul.hashicorp.com/v1alpha1
kind: ServiceIntentions
metadata:
  name: zipkin
  namespace: tracing-demo
spec:
  destination:
    name: zipkin
  sources:
    - name: "*"
      action: allow
      description: "Allow all services to send traces to Zipkin"
```

Apply the intentions:

```bash
kubectl apply -f service-intentions.yaml
```

### Option 3: Using Consul CLI

```bash
# Get Consul server pod
CONSUL_POD=$(kubectl get pod -n consul -l component=server -o jsonpath='{.items[0].metadata.name}')

# Create intentions
kubectl exec -it $CONSUL_POD -n consul -- consul intention create frontend catalog
kubectl exec -it $CONSUL_POD -n consul -- consul intention create frontend cart
kubectl exec -it $CONSUL_POD -n consul -- consul intention create frontend checkout
kubectl exec -it $CONSUL_POD -n consul -- consul intention create cart catalog
kubectl exec -it $CONSUL_POD -n consul -- consul intention create checkout cart
kubectl exec -it $CONSUL_POD -n consul -- consul intention create checkout inventory
kubectl exec -it $CONSUL_POD -n consul -- consul intention create checkout payment
kubectl exec -it $CONSUL_POD -n consul -- consul intention create '*' zipkin
```

## Verifying Intentions

### Check Intentions in UI

1. Go to **Intentions** in Consul UI
2. You should see all the allow rules listed
3. Go back to **Services** → **Topology**
4. Connections should now show as "Allowed" instead of "Connection Denied"

### Check Intentions via CLI

```bash
# List all intentions
kubectl exec -it $CONSUL_POD -n consul -- consul intention list

# Check specific intention
kubectl exec -it $CONSUL_POD -n consul -- consul intention get frontend catalog
```

### Check Intentions via kubectl

```bash
# List ServiceIntentions CRDs
kubectl get serviceintentions -n tracing-demo

# View details
kubectl describe serviceintention catalog -n tracing-demo
```

## Testing with "deny" Default Policy

If you want to test with a secure-by-default configuration:

1. **Update Consul Helm values** to set `defaultPolicy: "deny"`
2. **Upgrade Consul**: `helm upgrade consul hashicorp/consul -n consul -f values.yaml`
3. **Traffic will be blocked** until you create intentions
4. **Create intentions** using one of the methods above
5. **Verify traffic flows** again

## Summary

| Scenario | Default Policy | Intentions Exist | Traffic Flows? | UI Shows |
|----------|---------------|------------------|----------------|----------|
| Current (likely) | allow | No | ✅ Yes | ⚠️ "Connection Denied" (warning) |
| With intentions | allow | Yes | ✅ Yes | ✅ "Allowed" |
| Production (recommended) | deny | No | ❌ No | ❌ "Connection Denied" (blocked) |
| Production with intentions | deny | Yes | ✅ Yes | ✅ "Allowed" |

## Key Takeaways

1. **"Connection Denied" in UI ≠ Traffic Actually Blocked** (if default_policy = "allow")
2. **mTLS is always enforced** regardless of intentions or default policy
3. **Intentions are authorization rules**, not encryption rules
4. **Best practice**: Use `default_policy = "deny"` + explicit intentions for zero-trust security
5. **For demo/dev**: `default_policy = "allow"` is fine, but create intentions anyway for visibility

## Related Documentation

- [Consul Intentions](https://developer.hashicorp.com/consul/docs/connect/intentions)
- [Consul ACL System](https://developer.hashicorp.com/consul/docs/security/acl)
- [ServiceIntentions CRD](https://developer.hashicorp.com/consul/docs/k8s/crds/serviceintentions)