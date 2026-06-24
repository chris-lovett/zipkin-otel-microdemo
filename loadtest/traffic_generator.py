#!/usr/bin/env python3
"""
Traffic generator for the Flask app shown in the prompt.

It produces a realistic mix of:
- lightweight health checks
- normal "/" reads
- /api requests that may return success or app-configured errors
- /upstream-service calls to healthy and unhealthy endpoints
- /dig DNS lookups with valid, NXDOMAIN, NoAnswer, and timeout-ish cases

This helps emit the app's potential traces:
- GET /
- GET /health
- GET /api
- POST /upstream-service
- http_get_upstream
- GET /dig
- dns_lookup

Example:
  python traffic_generator.py --base-url http://localhost:8080 --duration 300 --rps 2

Optional environment variables:
  TARGET_BASE_URL=http://localhost:8080
  PYTHON_DEMO_A_URL=http://localhost:8091
"""

import argparse
import random
import time
import uuid
import json
import sys
import os
from concurrent.futures import ThreadPoolExecutor
from typing import Dict, Any, Optional

import requests


DEFAULT_HEADERS = {
    "User-Agent": "zipkin-otel-microdemo-traffic-generator/1.0",
    "Accept": "application/json, text/plain;q=0.9, */*;q=0.8",
}


def make_session() -> requests.Session:
    s = requests.Session()
    s.headers.update(DEFAULT_HEADERS)
    return s


def b3_headers(sampled: bool = True) -> Dict[str, str]:
    trace_id = uuid.uuid4().hex
    span_id = uuid.uuid4().hex[:16]
    parent_span_id = uuid.uuid4().hex[:16]
    return {
        "X-B3-TraceId": trace_id,
        "X-B3-SpanId": span_id,
        "X-B3-ParentSpanId": parent_span_id,
        "X-B3-Sampled": "1" if sampled else "0",
        "X-B3-Flags": "0",
    }


def call_root(session: requests.Session, base_url: str, timeout: int) -> Dict[str, Any]:
    url = f"{base_url.rstrip('/')}/"
    r = session.get(url, timeout=timeout, headers=b3_headers())
    return {"name": "root", "url": url, "status": r.status_code, "ok": r.ok}


def call_health(session: requests.Session, base_url: str, timeout: int) -> Dict[str, Any]:
    url = f"{base_url.rstrip('/')}/health"
    r = session.get(url, timeout=timeout, headers=b3_headers())
    return {"name": "health", "url": url, "status": r.status_code, "ok": r.ok}


def call_api(session: requests.Session, base_url: str, timeout: int) -> Dict[str, Any]:
    url = f"{base_url.rstrip('/')}/api"
    r = session.get(url, timeout=timeout, headers=b3_headers())
    return {"name": "api", "url": url, "status": r.status_code, "ok": r.ok}


def call_upstream(
    session: requests.Session,
    base_url: str,
    timeout: int,
    target_url: str,
    verify_ssl: bool = True,
    upstream_timeout: int = 5,
) -> Dict[str, Any]:
    url = f"{base_url.rstrip('/')}/upstream-service"
    payload = {
        "url": target_url,
        "verify_ssl": verify_ssl,
        "timeout": upstream_timeout,
    }
    r = session.post(url, json=payload, timeout=timeout, headers=b3_headers())
    return {
        "name": "upstream-service",
        "url": url,
        "status": r.status_code,
        "ok": r.ok,
        "target_url": target_url,
    }


def call_dig(
    session: requests.Session,
    base_url: str,
    timeout: int,
    hostname: str,
    record_type: str = "A",
) -> Dict[str, Any]:
    url = f"{base_url.rstrip('/')}/dig"
    r = session.get(
        url,
        params={"hostname": hostname, "type": record_type},
        timeout=timeout,
        headers=b3_headers(),
    )
    return {
        "name": "dig",
        "url": url,
        "status": r.status_code,
        "ok": r.ok,
        "hostname": hostname,
        "record_type": record_type,
    }


def call_python_demo_chain(
    session: requests.Session,
    service_a_url: str,
    timeout: int,
) -> Dict[str, Any]:
    url = f"{service_a_url.rstrip('/')}/demo"
    r = session.get(url, timeout=timeout, headers=b3_headers())
    return {"name": "python-demo-chain", "url": url, "status": r.status_code, "ok": r.ok}


def safe_run(fn, *args, **kwargs) -> Dict[str, Any]:
    try:
        return fn(*args, **kwargs)
    except requests.RequestException as exc:
        return {
            "name": getattr(fn, "__name__", "request"),
            "ok": False,
            "error": f"{type(exc).__name__}: {exc}",
        }
    except Exception as exc:
        return {
            "name": getattr(fn, "__name__", "request"),
            "ok": False,
            "error": f"{type(exc).__name__}: {exc}",
        }


def weighted_choice(enable_python_demo: bool) -> str:
    choices = [
        ("health", 20),
        ("root", 15),
        ("api", 25),
        ("upstream_ok", 18),
        ("upstream_fail", 8),
        ("dig_ok", 8),
        ("dig_nxdomain", 3),
        ("dig_noanswer", 2),
        ("dig_timeoutish", 1),
    ]
    if enable_python_demo:
        choices.append(("python_demo_chain", 10))

    total = sum(weight for _, weight in choices)
    pick = random.uniform(0, total)
    upto = 0
    for name, weight in choices:
        if upto + weight >= pick:
            return name
        upto += weight
    return choices[-1][0]


def scenario(
    session: requests.Session,
    base_url: str,
    timeout: int,
    python_demo_a_url: Optional[str],
) -> Dict[str, Any]:
    choice = weighted_choice(enable_python_demo=bool(python_demo_a_url))

    if choice == "health":
        return safe_run(call_health, session, base_url, timeout)

    if choice == "root":
        return safe_run(call_root, session, base_url, timeout)

    if choice == "api":
        return safe_run(call_api, session, base_url, timeout)

    if choice == "upstream_ok":
        targets = [
            "https://example.com",
            "https://httpbin.org/get",
            f"{base_url.rstrip('/')}/health",
            f"{base_url.rstrip('/')}/api",
        ]
        return safe_run(
            call_upstream,
            session,
            base_url,
            timeout,
            random.choice(targets),
            True,
            random.choice([3, 5, 10]),
        )

    if choice == "upstream_fail":
        targets = [
            "http://127.0.0.1:1",
            "http://nonexistent.invalid",
            "https://expired.badssl.com",
        ]
        target = random.choice(targets)
        verify_ssl = not target.endswith("expired.badssl.com")
        return safe_run(
            call_upstream,
            session,
            base_url,
            timeout,
            target,
            verify_ssl,
            random.choice([1, 2, 3]),
        )

    if choice == "dig_ok":
        hostnames = [
            ("example.com", "A"),
            ("google.com", "A"),
            ("github.com", "A"),
            ("example.com", "AAAA"),
            ("gmail.com", "MX"),
        ]
        hostname, record_type = random.choice(hostnames)
        return safe_run(call_dig, session, base_url, timeout, hostname, record_type)

    if choice == "dig_nxdomain":
        hostname = f"no-such-host-{uuid.uuid4().hex[:8]}.invalid"
        return safe_run(call_dig, session, base_url, timeout, hostname, "A")

    if choice == "dig_noanswer":
        candidates = [
            ("example.com", "MX"),
            ("github.com", "TXT"),
        ]
        hostname, record_type = random.choice(candidates)
        return safe_run(call_dig, session, base_url, timeout, hostname, record_type)

    if choice == "dig_timeoutish":
        hostname = "10.255.255.1"
        return safe_run(call_dig, session, base_url, timeout, hostname, "A")

    if choice == "python_demo_chain" and python_demo_a_url:
        return safe_run(call_python_demo_chain, session, python_demo_a_url, timeout)

    return safe_run(call_health, session, base_url, timeout)


def print_result(result: Dict[str, Any]) -> None:
    stamp = time.strftime("%Y-%m-%d %H:%M:%S")
    if result.get("ok"):
        extra = []
        if "target_url" in result:
            extra.append(f"target={result['target_url']}")
        if "hostname" in result:
            extra.append(f"host={result['hostname']} type={result.get('record_type')}")
        print(
            f"[{stamp}] OK   scenario={result.get('name')} status={result.get('status')} "
            + " ".join(extra)
        )
    else:
        print(
            f"[{stamp}] FAIL scenario={result.get('name')} "
            f"status={result.get('status')} error={result.get('error')}"
        )


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate traced traffic for the microdemo app.")
    parser.add_argument("--base-url", default=os.getenv("TARGET_BASE_URL", "http://localhost:8080"))
    parser.add_argument("--python-demo-a-url", default=os.getenv("PYTHON_DEMO_A_URL"))
    parser.add_argument("--duration", type=int, default=300, help="Run duration in seconds")
    parser.add_argument("--rps", type=float, default=2.0, help="Approximate requests per second")
    parser.add_argument("--concurrency", type=int, default=4, help="Worker thread count")
    parser.add_argument("--timeout", type=int, default=15, help="Client timeout in seconds")
    parser.add_argument("--seed", type=int, default=None, help="Random seed for repeatability")
    args = parser.parse_args()

    if args.seed is not None:
        random.seed(args.seed)

    total_requests = max(1, int(args.duration * args.rps))
    sleep_between = max(0.0, 1.0 / max(args.rps, 0.001))

    print(json.dumps({
        "base_url": args.base_url,
        "python_demo_a_url": args.python_demo_a_url,
        "duration": args.duration,
        "rps": args.rps,
        "concurrency": args.concurrency,
        "timeout": args.timeout,
        "total_requests": total_requests,
    }, indent=2))

    start = time.time()
    submitted = 0
    completed = 0
    success = 0
    failed = 0

    with ThreadPoolExecutor(max_workers=args.concurrency) as executor:
        futures = []
        while submitted < total_requests and time.time() - start < args.duration:
            session = make_session()
            futures.append(
                executor.submit(
                    scenario,
                    session,
                    args.base_url,
                    args.timeout,
                    args.python_demo_a_url,
                )
            )
            submitted += 1
            time.sleep(sleep_between)

        for future in futures:
            result = future.result()
            completed += 1
            if result.get("ok"):
                success += 1
            else:
                failed += 1
            print_result(result)

    print("\nSummary")
    print("-------")
    print(f"submitted : {submitted}")
    print(f"completed : {completed}")
    print(f"success   : {success}")
    print(f"failed    : {failed}")

    return 0 if completed > 0 else 1


if __name__ == "__main__":
    sys.exit(main())
