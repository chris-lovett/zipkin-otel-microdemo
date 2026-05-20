# Consul Intentions - Concepts and Policy Guidance

This document is a concise reference for service intentions and ACL policy behavior.

For operational setup and validation workflow, use:
- [docs/observability/06-intentions-and-acls.md](docs/observability/06-intentions-and-acls.md)
- [docs/observability/05-operations-and-troubleshooting.md](docs/observability/05-operations-and-troubleshooting.md)

## Core Concepts

- Intentions define explicit source-to-destination authorization between services.
- ACL default policy controls behavior when no explicit intention exists.
- Allow-by-default can mask missing intentions in non-production setups.
- Deny-by-default with explicit intentions is the recommended production posture.

## Verification Criteria

A healthy intentions posture means:
- required service pairs are explicitly allowed
- unintended service paths are denied
- topology and service behavior match the declared policy model

## Repository Assets

- [service-intentions.yaml](service-intentions.yaml)
- [scripts/observability](scripts/observability)
- [docs/archive/README.md](docs/archive/README.md)
