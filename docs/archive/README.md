# Archived Documentation

This directory contains historical documentation from the metrics implementation and troubleshooting process. These files are preserved for reference but have been superseded by the consolidated [`PROJECT_STATUS.md`](../../PROJECT_STATUS.md) in the root directory.

## Why These Files Were Archived

During the metrics implementation (May 2024), multiple documentation files were created as we iterated through different solutions. This resulted in:
- Redundant information across multiple files
- Conflicting solutions from different implementation attempts
- Confusion about which approach was actually implemented
- Bloated documentation structure

## What's in This Archive

### Metrics Implementation Iterations

1. **METRICS_FIX_SUMMARY.md** - Early attempt focusing on disabling metrics merging due to 404 errors
2. **METRICS_SOLUTION.md** - Prometheus sidecar pattern proposal to work around bind address issue
3. **SOLUTION_COMPLETE.md** - Final working solution with OpenShift-specific configuration
4. **OPENSHIFT_MONITORING_FIX.md** - Discovery of required OpenShift user-monitoring labels
5. **ENVOY_METRICS_ISSUE.md** - Analysis of port 20200 vs 19000 confusion

### Grafana Dashboard Documentation

1. **GRAFANA_STATUS.md** - Dashboard verification and access information
2. **GRAFANA_DASHBOARD_GUIDE.md** - How to use the dashboard
3. **DASHBOARD_FIX_SUMMARY.md** - Namespace variable fix implementation

### Troubleshooting Guides

1. **TROUBLESHOOTING_NO_METRICS.md** - Comprehensive troubleshooting guide
2. **QUICK_FIX_GUIDE.md** - Quick reference version
3. **ROOT_CAUSE_ANALYSIS.md** - Discovery that load test was bypassing the mesh

## Current Documentation

For current, accurate information, refer to:

- **[PROJECT_STATUS.md](../../PROJECT_STATUS.md)** - Complete current status and working solution
- **[README.md](../../README.md)** - Main project documentation
- **[CONSUL_METRICS.md](../../CONSUL_METRICS.md)** - Consul UI metrics configuration
- **[CONSUL_TOPOLOGY.md](../../CONSUL_TOPOLOGY.md)** - Service mesh topology
- **[loadtest/README.md](../../loadtest/README.md)** - Load testing documentation

## Historical Value

These archived documents are useful for:
- Understanding the evolution of the solution
- Learning from troubleshooting approaches
- Reference for similar issues in other projects
- Documentation of what didn't work and why

## Key Learnings

1. **Prometheus Sidecar Pattern** - Necessary when consul-dataplane binds to localhost only
2. **OpenShift User Workload Monitoring** - Requires specific labels on namespace and ServiceMonitor
3. **Mesh-Aware Load Testing** - Traffic must flow through Envoy sidecars to generate metrics
4. **Iterative Problem Solving** - Multiple attempts led to the final working solution

---

**Note**: Do not use these archived documents as implementation guides. They represent historical iterations and may contain outdated or incorrect information. Always refer to the current documentation in the root directory.