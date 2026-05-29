"""
Service B – middle of the Python Zipkin demo chain.

Receives a request from service-a, continues the trace, and calls service-c.
"""
import os
import requests
from flask import Flask, request, jsonify
from py_zipkin.zipkin import zipkin_span, ZipkinAttrs
from py_zipkin import thread_local as _tl

from tracing import HttpTransport, ENCODING

SERVICE_NAME = os.environ.get("SERVICE_NAME", "service-b")
PORT = int(os.environ.get("PORT", 8092))
SERVICE_C_URL = os.environ.get("SERVICE_C_URL", "http://localhost:8093")

app = Flask(__name__)


def _extract_b3(headers):
    """
    Parse incoming B3 headers into a ZipkinAttrs object so that py-zipkin
    can create a child span in the same distributed trace.

    Returns None if no trace-id header is present (i.e. the caller did not
    start a trace), which causes zipkin_span to begin a brand-new trace.
    """
    trace_id = headers.get("X-B3-TraceId")
    if not trace_id:
        return None
    return ZipkinAttrs(
        trace_id=trace_id,
        span_id=headers.get("X-B3-SpanId"),
        parent_span_id=headers.get("X-B3-ParentSpanId"),
        flags=headers.get("X-B3-Flags", "0"),
        is_sampled=headers.get("X-B3-Sampled", "1") == "1",
    )


def _outgoing_b3_headers():
    """Build B3 headers from the currently active span for downstream calls."""
    attrs = _tl.get_zipkin_attrs()
    if not attrs:
        return {}
    return {
        "X-B3-TraceId": attrs.trace_id,
        "X-B3-SpanId": attrs.span_id,
        "X-B3-Sampled": "1" if attrs.is_sampled else "0",
        "X-B3-Flags": attrs.flags or "0",
    }


@app.route("/health")
def health():
    return jsonify({"status": "ok", "service": SERVICE_NAME})


@app.route("/work")
def work():
    # Extract the parent span context propagated by service-a.
    incoming_attrs = _extract_b3(request.headers)

    # Create a child span that continues the same distributed trace.
    with zipkin_span(
        service_name=SERVICE_NAME,
        span_name="GET /work",
        transport_handler=HttpTransport(),
        sample_rate=100,
        encoding=ENCODING,
        zipkin_attrs=incoming_attrs,
    ):
        # Forward to service-c, propagating the current span as parent.
        try:
            resp = requests.get(
                f"{SERVICE_C_URL}/work",
                headers=_outgoing_b3_headers(),
                timeout=10,
            )
            resp.raise_for_status()
            chain_result = resp.json()
        except requests.RequestException as exc:
            return jsonify({"error": f"call to service-c failed: {type(exc).__name__}: {exc}"}), 502

    return jsonify({
        "service": SERVICE_NAME,
        "downstream": chain_result,
    })


if __name__ == "__main__":
    print(f"[{SERVICE_NAME}] listening on port {PORT}")
    app.run(host="0.0.0.0", port=PORT)
