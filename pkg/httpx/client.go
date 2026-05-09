// Package httpx provides an instrumented HTTP client that propagates Zipkin B3 headers.
package httpx

import (
	"net/http"

	zipkin "github.com/openzipkin/zipkin-go"
	zipkinhttp "github.com/openzipkin/zipkin-go/middleware/http"
)

// NewClient returns an *http.Client whose transport injects Zipkin B3 headers
// into every outbound request, enabling end-to-end trace propagation.
func NewClient(tracer *zipkin.Tracer) *http.Client {
	transport, err := zipkinhttp.NewTransport(
		tracer,
		zipkinhttp.TransportTrace(true),
	)
	if err != nil {
		// NewTransport only errors when tracer is nil; treat as hard failure.
		panic("httpx.NewClient: failed to create Zipkin transport: " + err.Error())
	}
	return &http.Client{Transport: transport}
}
