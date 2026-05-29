"""
Service A – entry point of the Python Zipkin demo.

Call chain:  client  →  service-a  →  service-b  →  service-c

Trigger the full chain:
    GET http://localhost:8091/demo
"""
import os
import requests
from flask import Flask, jsonify
from py_zipkin.zipkin import zipkin_span
from py_zipkin import thread_local as _tl

# Import shared helpers from the tracing module sitting in the same directory.
from tracing import HttpTransport, ENCODING

SERVICE_NAME = os.environ.get("SERVICE_NAME", "service-a")
PORT = int(os.environ.get("PORT", 8091))
SERVICE_B_URL = os.environ.get("SERVICE_B_URL", "http://localhost:8092")

app = Flask(__name__)


def _outgoing_b3_headers():
    """
    Build B3 propagation headers from the currently active span so that the
    downstream service can join the same distributed trace.
    """
    attrs = _tl.get_zipkin_attrs()
    if not attrs:
        return {}
    return {
        "X-B3-TraceId": attrs.trace_id,
        # The receiver will treat this span_id as their parent span.
        "X-B3-SpanId": attrs.span_id,
        "X-B3-Sampled": "1" if attrs.is_sampled else "0",
        "X-B3-Flags": attrs.flags or "0",
    }


@app.route("/health")
def health():
    return jsonify({"status": "ok", "service": SERVICE_NAME})


@app.route("/demo")
def demo():
    # Start a new root span.  sample_rate=100 means always sample.
    with zipkin_span(
        service_name=SERVICE_NAME,
        span_name="GET /demo",
        transport_handler=HttpTransport(),
        sample_rate=100,
        encoding=ENCODING,
    ):
        # Call service-b and propagate the current span as the B3 parent.
        try:
            resp = requests.get(
                f"{SERVICE_B_URL}/work",
                headers=_outgoing_b3_headers(),
                timeout=10,
            )
            resp.raise_for_status()
            chain_result = resp.json()
        except requests.RequestException as exc:
            return jsonify({"error": f"call to service-b failed: {type(exc).__name__}: {exc}"}), 502

    return jsonify({
        "service": SERVICE_NAME,
        "message": "Trace complete! Open Zipkin UI to inspect the distributed trace.",
        "chain": chain_result,
    })


if __name__ == "__main__":
    print(f"[{SERVICE_NAME}] listening on port {PORT}")
    app.run(host="0.0.0.0", port=PORT)
