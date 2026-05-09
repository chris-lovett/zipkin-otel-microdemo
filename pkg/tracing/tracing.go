// Package tracing provides Zipkin tracer initialisation and HTTP middleware helpers
// shared across all microservices.
package tracing

import (
	"log"
	"net/http"
	"os"
	"strconv"

	zipkin "github.com/openzipkin/zipkin-go"
	zipkinhttp "github.com/openzipkin/zipkin-go/middleware/http"
	"github.com/openzipkin/zipkin-go/model"
	httpreporter "github.com/openzipkin/zipkin-go/reporter/http"
)

// Init creates a Zipkin tracer configured from environment variables:
//
//	ZIPKIN_URL    – collector endpoint (default: http://localhost:9411/api/v2/spans)
//	SERVICE_NAME  – local service name (required; typically set per service)
//	SAMPLE_RATE   – fraction of traces to sample (default: 1.0)
//
// It returns the tracer and a cleanup function that must be called on shutdown.
func Init(serviceName string) (*zipkin.Tracer, func()) {
	zipkinURL := getenv("ZIPKIN_URL", "http://localhost:9411/api/v2/spans")
	if sn := os.Getenv("SERVICE_NAME"); sn != "" {
		serviceName = sn
	}
	sampleRate := 1.0
	if sr := os.Getenv("SAMPLE_RATE"); sr != "" {
		if v, err := strconv.ParseFloat(sr, 64); err == nil {
			sampleRate = v
		}
	}

	reporter := httpreporter.NewReporter(zipkinURL)

	endpoint, err := zipkin.NewEndpoint(serviceName, "")
	if err != nil {
		log.Fatalf("[%s] could not create Zipkin endpoint: %v", serviceName, err)
	}

	sampler, err := zipkin.NewBoundarySampler(sampleRate, 1)
	if err != nil {
		log.Fatalf("[%s] could not create Zipkin sampler: %v", serviceName, err)
	}

	tracer, err := zipkin.NewTracer(
		reporter,
		zipkin.WithLocalEndpoint(endpoint),
		zipkin.WithSampler(sampler),
		zipkin.WithSharedSpans(false),
		zipkin.WithTraceID128Bit(true),
	)
	if err != nil {
		log.Fatalf("[%s] could not create Zipkin tracer: %v", serviceName, err)
	}

	log.Printf("[%s] Zipkin tracer initialised (collector=%s, sampleRate=%.2f)", serviceName, zipkinURL, sampleRate)

	cleanup := func() {
		if err := reporter.Close(); err != nil {
			log.Printf("[%s] error closing Zipkin reporter: %v", serviceName, err)
		}
	}
	return tracer, cleanup
}

// Middleware returns an HTTP server middleware that creates Zipkin server spans,
// extracts B3 propagation headers from incoming requests, and stores the active
// span in the request context via zipkin.NewContext.
func Middleware(tracer *zipkin.Tracer) func(http.Handler) http.Handler {
	return zipkinhttp.NewServerMiddleware(
		tracer,
		zipkinhttp.TagResponseSize(true),
	)
}

// SpanFromContext extracts the current Zipkin span from ctx, returning nil if absent.
// Callers can use this to add tags to the active server span.
func SpanFromContext(r *http.Request) zipkin.Span {
	return zipkin.SpanFromContext(r.Context())
}

// Tag adds a key/value tag to span if span is not nil.
func Tag(span zipkin.Span, key, value string) {
	if span != nil {
		span.Tag(key, value)
	}
}

// SetError marks span as errored.
func SetError(span zipkin.Span, msg string) {
	if span != nil {
		span.Tag("error", msg)
	}
}

// StartChildSpan starts a new child span with the given name from the request context.
// The caller is responsible for calling span.Finish().
func StartChildSpan(tracer *zipkin.Tracer, r *http.Request, name string) (zipkin.Span, *http.Request) {
	parent := zipkin.SpanFromContext(r.Context())
	var span zipkin.Span
	if parent != nil {
		span = tracer.StartSpan(name, zipkin.Parent(parent.Context()))
	} else {
		span = tracer.StartSpan(name, zipkin.Kind(model.Client))
	}
	ctx := zipkin.NewContext(r.Context(), span)
	return span, r.WithContext(ctx)
}

func getenv(key, defaultVal string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return defaultVal
}
