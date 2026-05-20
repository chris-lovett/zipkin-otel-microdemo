# Intentions and ACLs

This section covers Consul service-to-service authorization behavior and production security posture.

## Why This Matters

Intentions and ACL policy determine whether traffic is explicitly allowed between services.

Key points:
- traffic can still flow without explicit intentions when default ACL policy is allow
- production posture should be deny by default with explicit allow intentions
- topology warnings about denied connections can indicate missing explicit intentions even when traffic still flows under allow policy

## Recommended Production Posture

- set ACL default policy to deny
- define explicit service intentions for required paths
- verify expected service pairs only

## Implementation Assets

- [../../service-intentions.yaml](../../service-intentions.yaml)
- [../../CONSUL_INTENTIONS.md](../../CONSUL_INTENTIONS.md)

## Verification

1. List intentions and confirm expected source and destination pairs.
2. Validate intended traffic succeeds and non-intended traffic is blocked.
3. Review topology and connection status in Consul UI.

## Related

- [02-service-monitoring.md](02-service-monitoring.md)
- [05-operations-and-troubleshooting.md](05-operations-and-troubleshooting.md)
