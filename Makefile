SERVICES := frontend catalog cart checkout payment inventory
IMAGE_REGISTRY ?= ghcr.io/chris-lovett/zipkin-otel-microdemo
IMAGE_TAG ?= 0.1.0

.PHONY: build-images push-images

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
