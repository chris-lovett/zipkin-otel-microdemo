#!/usr/bin/env python3
"""Align Data Plane Performance dashboard with Consul UI template variables."""
import json
import sys
from copy import deepcopy


def patch_expr(expr: str) -> str:
    if not isinstance(expr, str):
        return expr

    out = expr

    # Top resource panels: use kube-state-metrics labels that exist on OpenShift and
    # scope pods by selected service name.
    if "container_memory_working_set_bytes" in out and "kube_pod_container_resource_limits" in out:
        return (
            '100 * max by (pod) ('
            'container_memory_working_set_bytes{namespace=~"$k8s_namespace", container!="", pod=~"$service-.*"} '
            '/ on(namespace,pod,container) group_left '
            'kube_pod_container_resource_limits{namespace=~"$k8s_namespace", resource="memory", unit="byte", container!="", pod=~"$service-.*"}'
            ')'
        )

    if "container_cpu_usage_seconds_total" in out and "kube_pod_container_resource_limits" in out:
        return (
            '100 * max by (pod) ('
            'rate(container_cpu_usage_seconds_total{namespace=~"$k8s_namespace", container!="", pod=~"$service-.*"}[5m]) '
            '/ on(namespace,pod,container) group_left '
            'kube_pod_container_resource_limits{namespace=~"$k8s_namespace", resource="cpu", unit="core", container!="", pod=~"$service-.*"}'
            ')'
        )

    if "container_cpu_cfs_throttled_seconds_total" in out:
        return 'rate(container_cpu_cfs_throttled_seconds_total{namespace=~"$k8s_namespace", pod=~"$service-.*"}[5m])'

    # Service-scoped upstream connection count.
    if "envoy_cluster_upstream_cx_active" in out:
        return (
            'sum('
            'envoy_cluster_upstream_cx_active{'
            'consul_source_namespace=~"$namespace",'
            'consul_source_service=~"$service",'
            'consul_destination_service!="consul-telemetry-collector",'
            'envoy_cluster_name!~"consul-dataplane|consul_telemetry_collector_loopback|prometheus.*|local_app|original-.*"'
            '}'
            ')'
        )

    # Requests/sec should be upstream requests for the selected service, not only
    # public_listener downstream traffic.
    if 'envoy_http_downstream_rq_total' in out and 'public_listener' in out:
        return (
            'sum(rate(envoy_cluster_upstream_rq_total{'
            'consul_source_namespace=~"$namespace",'
            'consul_source_service=~"$service",'
            'consul_destination_service!="consul-telemetry-collector",'
            'envoy_cluster_name!~"consul_telemetry_collector_loopback|consul-dataplane|local_app|original-.*"'
            '}[5m]))'
        )

    # Latency panels should use Consul source service labels.
    if "envoy_cluster_upstream_rq_time_bucket" in out:
        return (
            out.replace('namespace=~"$namespace"', 'consul_source_namespace=~"$namespace"')
            .replace('namespace="$namespace"', 'consul_source_namespace=~"$namespace"')
            .replace('local_cluster=~"$app"', 'consul_source_service=~"$service"')
            .replace('local_cluster="$app"', 'consul_source_service=~"$service"')
            .replace('local_cluster=~"$service"', 'consul_source_service=~"$service"')
        )

    # HTTP status should use upstream response classes for the selected source service.
    if "envoy_http_downstream_rq_xx" in out:
        return (
            'sum by(consul_source_service, envoy_response_code_class) ('
            'increase(envoy_cluster_upstream_rq_xx{'
            'consul_source_namespace=~"$namespace",'
            'consul_source_service=~"$service",'
            'consul_destination_service!="consul-telemetry-collector"'
            '}[5m]))'
        )

    if "envoy_cluster_upstream_rq_active" in out:
        return (
            'sum by(consul_source_service, consul_destination_service) ('
            'envoy_cluster_upstream_rq_active{'
            'consul_source_namespace=~"$namespace",'
            'consul_source_service=~"$service",'
            'consul_destination_service!="consul-telemetry-collector",'
            'envoy_cluster_name!~"consul_telemetry_collector_loopback|consul-dataplane|local_app|original-.*"'
            '})'
        )

    if "envoy_listener_downstream_cx_overload_reject" in out or "envoy_listener_downstream_global_cx_overflow" in out:
        return (
            out.replace('{}', '{consul_source_namespace=~"$namespace",consul_source_service=~"$service"}')
               .replace('namespace=~"$namespace"', 'consul_source_namespace=~"$namespace"')
               .replace('namespace="$namespace"', 'consul_source_namespace=~"$namespace"')
        )

    if "envoy_cluster_upstream_rq_time_count" in out and "envoy_cluster_upstream_rq_time_bucket" in out:
        return (
            out.replace('namespace=~"$namespace"', 'consul_source_namespace=~"$namespace"')
               .replace('namespace="$namespace"', 'consul_source_namespace=~"$namespace"')
               .replace('envoy_cluster_name!~"prometheus_backend|local_app"', 'consul_source_service=~"$service",consul_destination_service!="consul-telemetry-collector",envoy_cluster_name!~"prometheus_backend|local_app|consul_telemetry_collector_loopback|consul-dataplane"')
        )

    # Generic Kubernetes/cAdvisor panels — keep kube namespace, resolved from Consul selection.
    if "container_" in out or "container_cpu" in out or "container_memory" in out:
        return (
            out.replace('namespace=~"$namespace"', 'namespace=~"$k8s_namespace"')
               .replace('namespace="$namespace"', 'namespace=~"$k8s_namespace"')
               .replace('pod=~"$app.*"', 'pod=~"$service-.*"')
               .replace('pod=~"$service.*"', 'pod=~"$service-.*"')
        )

    # Generic Envoy / mesh panels — use Consul labels.
    out = out.replace('namespace=~"$namespace"', 'consul_source_namespace=~"$namespace"')
    out = out.replace('namespace="$namespace"', 'consul_source_namespace=~"$namespace"')
    out = out.replace('app="$app"', 'consul_source_service=~"$service"')
    out = out.replace('app=~"$app"', 'consul_source_service=~"$service"')
    out = out.replace('app="$service"', 'consul_source_service=~"$service"')
    out = out.replace('app=~"$service"', 'consul_source_service=~"$service"')
    out = out.replace('local_cluster="$app"', 'consul_source_service=~"$service"')
    out = out.replace('local_cluster=~"$app"', 'consul_source_service=~"$service"')
    out = out.replace('local_cluster=~"$service"', 'consul_source_service=~"$service"')
    out = out.replace('pod=~"$app.*"', 'pod=~"$service-.*"')
    out = out.replace('pod=~"$service.*"', 'pod=~"$service-.*"')
    return out


def walk_panels(panels):
    for p in panels:
        if "panels" in p:
            walk_panels(p["panels"])
        for t in p.get("targets", []):
            if "expr" in t:
                t["expr"] = patch_expr(t["expr"])


def patch_variables(dash):
    new_list = []
    k8s_var = {
        "name": "k8s_namespace",
        "type": "query",
        "hide": 2,
        "label": "K8s namespace",
        "datasource": dash["templating"]["list"][0].get("datasource"),
        "definition": 'label_values(envoy_cluster_upstream_rq_total{consul_source_namespace="$namespace", consul_source_service="$service"}, namespace)',
        "query": {
            "query": 'label_values(envoy_cluster_upstream_rq_total{consul_source_namespace="$namespace", consul_source_service="$service"}, namespace)',
            "refId": "StandardVariableQuery",
        },
        "refresh": 2,
        "sort": 1,
        "multi": False,
        "includeAll": False,
    }

    for v in dash["templating"]["list"]:
        v = deepcopy(v)
        name = v.get("name")
        if name == "namespace":
            v["label"] = "Consul namespace"
            q = "label_values(envoy_cluster_upstream_rq_total, consul_source_namespace)"
            v["definition"] = q
            if isinstance(v.get("query"), dict):
                v["query"]["query"] = q
            v["current"] = {"selected": True, "text": "default", "value": "default"}
        elif name in ("app", "service"):
            v["name"] = "service"
            v["label"] = "Service"
            q = 'label_values(envoy_cluster_upstream_rq_total{consul_source_namespace="$namespace"}, consul_source_service)'
            v["definition"] = q
            if isinstance(v.get("query"), dict):
                v["query"]["query"] = q
            elif isinstance(v.get("query"), str):
                v["query"] = q
            v["current"] = {"selected": True, "text": "cart", "value": "cart"}
        new_list.append(v)

    if not any(x["name"] == "k8s_namespace" for x in new_list):
        new_list.append(k8s_var)
    dash["templating"]["list"] = new_list


def main():
    dash = json.load(sys.stdin)
    patch_variables(dash)
    walk_panels(dash.get("panels", []))
    # Panel titles still reference $app
    raw = json.dumps(dash).replace("$app", "$service")
    json.dump(json.loads(raw), sys.stdout, separators=(",", ":"))


if __name__ == "__main__":
    main()
