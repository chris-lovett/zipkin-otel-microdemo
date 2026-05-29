"""
Service C – end of the Python Zipkin demo chain.

Receives a request from service-b, continues the trace, and returns a response.
This is the last hop; no further downstream calls are made.
"""
import os
from flask import Flask, request, jsonify
from py_zipkin.zipkin import zipkin_span, ZipkinAttrs

from tracing import HttpTransport, ENCODING

SERVICE_NAME = os.environ.get("SERVICE_NAME", "service-c")
PORT = int(os.environ.get("PORT", 8093))

app = Flask(__name__)


def _extract_b3(headers):
    """Parse incoming B3 headers into a ZipkinAttrs parent-context object."""
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


@app.route("/health")
def health():
    return jsonify({"status": "ok", "service": SERVICE_NAME})


@app.route("/work")
def work():
    # Continue the distributed trace started by service-a.
    incoming_attrs = _extract_b3(request.headers)

    with zipkin_span(
        service_name=SERVICE_NAME,
        span_name="GET /work",
        transport_handler=HttpTransport(),
        sample_rate=100,
        encoding=ENCODING,
        zipkin_attrs=incoming_attrs,
    ):
        # End of the chain – return a simple result.
        result = {
            "service": SERVICE_NAME,
            "message": "Work done at the end of the chain.",
        }

    return jsonify(result)


if __name__ == "__main__":
    print(f"[{SERVICE_NAME}] listening on port {PORT}")
    app.run(host="0.0.0.0", port=PORT)
