"""
Shared Zipkin tracing helpers for the Python demo services.

Uses py-zipkin to create spans and send them to a Zipkin collector via HTTP.
B3 headers are used to propagate trace context between services.
"""
import os
import requests
from py_zipkin.transport import BaseTransportHandler
from py_zipkin import Encoding

# Zipkin collector endpoint – override with the ZIPKIN_URL environment variable.
ZIPKIN_URL = os.environ.get("ZIPKIN_URL", "http://localhost:9411/api/v2/spans")

# Use the Zipkin v2 JSON wire format so we can POST to /api/v2/spans.
ENCODING = Encoding.V2_JSON


class HttpTransport(BaseTransportHandler):
    """Sends encoded Zipkin spans to the collector over HTTP."""

    def get_max_payload_bytes(self):
        return None  # no size limit

    def send(self, payload):
        try:
            requests.post(
                ZIPKIN_URL,
                data=payload,
                headers={"Content-Type": "application/json"},
                timeout=5,
            )
        except Exception as exc:
            print(f"[tracing] failed to send spans to {ZIPKIN_URL}: {type(exc).__name__}: {exc}")
