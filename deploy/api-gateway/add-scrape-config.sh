#!/bin/bash
# Script to add consul-api-gateway scrape config to Prometheus

set -e

echo "Adding consul-api-gateway scrape config to Prometheus..."

# Get the current config
kubectl get cm prometheus-server -n observability -o yaml > /tmp/prometheus-config.yaml

# Check if the scrape config already exists
if grep -q "job_name: consul-api-gateway" /tmp/prometheus-config.yaml; then
    echo "consul-api-gateway scrape config already exists"
    exit 0
fi

# Create a Python script to add the scrape config
cat > /tmp/add_scrape.py << 'EOF'
import yaml
import sys

with open('/tmp/prometheus-config.yaml', 'r') as f:
    config = yaml.safe_load(f)

# Parse the prometheus.yml from the ConfigMap
prom_config = yaml.safe_load(config['data']['prometheus.yml'])

# Add the new scrape config
new_scrape_config = {
    'job_name': 'consul-api-gateway',
    'kubernetes_sd_configs': [{
        'role': 'pod',
        'namespaces': {'names': ['tracing-demo']}
    }],
    'relabel_configs': [
        {
            'source_labels': ['__meta_kubernetes_pod_label_component'],
            'action': 'keep',
            'regex': 'api-gateway'
        },
        {
            'source_labels': ['__meta_kubernetes_pod_annotation_prometheus_io_scrape'],
            'action': 'keep',
            'regex': 'true'
        },
        {
            'source_labels': ['__meta_kubernetes_pod_annotation_prometheus_io_path'],
            'action': 'replace',
            'target_label': '__metrics_path__',
            'regex': '(.+)'
        },
        {
            'source_labels': ['__address__', '__meta_kubernetes_pod_annotation_prometheus_io_port'],
            'action': 'replace',
            'regex': '([^:]+)(?::\\d+)?;(\\d+)',
            'replacement': '$1:$2',
            'target_label': '__address__'
        },
        {
            'source_labels': ['__meta_kubernetes_namespace'],
            'target_label': 'namespace'
        },
        {
            'source_labels': ['__meta_kubernetes_pod_name'],
            'target_label': 'pod'
        }
    ]
}

# Insert at the beginning of scrape_configs
prom_config['scrape_configs'].insert(0, new_scrape_config)

# Update the ConfigMap
config['data']['prometheus.yml'] = yaml.dump(prom_config, default_flow_style=False, sort_keys=False)

with open('/tmp/prometheus-config-updated.yaml', 'w') as f:
    yaml.dump(config, f, default_flow_style=False, sort_keys=False)

print("Updated config written to /tmp/prometheus-config-updated.yaml")
EOF

# Run the Python script
python3 /tmp/add_scrape.py

# Apply the updated config
kubectl apply -f /tmp/prometheus-config-updated.yaml

echo "Scrape config added successfully"
echo "Reloading Prometheus..."
kubectl rollout restart deployment/prometheus-server -n observability

echo "Done! Wait for Prometheus to reload..."

# Made with Bob
