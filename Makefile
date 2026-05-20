SERVICES := frontend catalog cart checkout payment inventory
IMAGE_REGISTRY ?= quay.io/chris_lovett/zipkin-otel-microdemo
IMAGE_TAG ?= 0.1.0
PLATFORMS ?= linux/amd64,linux/arm64

.PHONY: build-images push-images build-multiarch observability-sync-dashboards observability-verify observability-troubleshoot

build-images:
	@set -e; for svc in $(SERVICES); do \
		echo "Building $$svc"; \
		docker build --build-arg SERVICE=$$svc -t $(IMAGE_REGISTRY)/$$svc:$(IMAGE_TAG) .; \
	done

push-images: build-images
	@set -e; for svc in $(SERVICES); do \
		echo "Pushing $$svc"; \
		docker push $(IMAGE_REGISTRY)/$$svc:$(IMAGE_TAG); \
	done

build-multiarch:
	@echo "Building multi-architecture images for platforms: $(PLATFORMS)"
	@set -e; for svc in $(SERVICES); do \
		echo "Building $$svc for $(PLATFORMS)"; \
		docker buildx build --platform $(PLATFORMS) \
			--build-arg SERVICE=$$svc \
			-t $(IMAGE_REGISTRY)/$$svc:$(IMAGE_TAG) \
			--push \
			.; \
	done

observability-sync-dashboards:
	@./deploy/observability/sync-grafana-dashboards.sh

observability-verify:
	@./scripts/observability/check-consul-metrics.sh
	@./scripts/observability/diagnose-consul-metrics.sh
	@./scripts/observability/diagnose-envoy-metrics.sh
	@./scripts/observability/diagnose-topology.sh

observability-troubleshoot:
	@./scripts/observability/troubleshoot-no-metrics.sh
