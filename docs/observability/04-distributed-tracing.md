# Distributed Tracing

This section explains distributed tracing setup and verification for services running in this demo.

## Tracing Model

Request flow emits spans across services and collects traces in Zipkin.

Core goals:
- end-to-end request visibility across frontend, cart, catalog, checkout, payment, inventory
- span timing for service dependencies
- correlation with traffic and metrics from service monitoring

## Required Components

- application deployment from [charts/zipkin-otel-microdemo](../../charts/zipkin-otel-microdemo)
- zipkin service and route in tracing-demo namespace
- mesh traffic generation for realistic traces

## Verification

1. Generate traffic with [loadtest/mesh-load.sh](../../loadtest/mesh-load.sh)
2. Open Zipkin UI and search recent traces
3. Confirm traces include expected downstream services for checkout and cart flows
4. Compare trace timelines with topology and request-rate metrics

## Troubleshooting Signals

- traces missing entirely: verify Zipkin service and route
- partial traces: verify downstream service connectivity and app instrumentation path
- low trace volume: increase sustained traffic generation

## Related

- [../../DEMO_GUIDE.md](../../DEMO_GUIDE.md)
- [../../loadtest/README.md](../../loadtest/README.md)
