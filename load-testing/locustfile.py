"""
Netlix Platform — Load Test Scenarios

Distributed Locust load tests targeting the web and api services running
in the consul namespace on EKS.  The tests exercise:

  1. Full request chain: ALB -> web -> Envoy -> api (mTLS via Consul Connect)
  2. Health and readiness probes
  3. Sustained load to trigger HPA autoscaling

Usage (headless CI):
  locust --headless -u 200 -r 10 --run-time 5m \
         --host http://web.consul.svc.cluster.local:9090 \
         --csv results/load-test

Usage (web UI):
  locust --host http://web.consul.svc.cluster.local:9090
"""

import json
import logging

from locust import HttpUser, between, events, task

logger = logging.getLogger(__name__)


class NetlixUser(HttpUser):
    """Simulates a typical user hitting the web frontend."""

    # Wait 1-3 seconds between requests (realistic browsing pattern)
    wait_time = between(1, 3)

    @task(6)
    def homepage(self):
        """GET / — exercises the full mesh path: web -> Envoy -> api."""
        with self.client.get("/", catch_response=True) as resp:
            if resp.status_code == 200:
                try:
                    body = resp.json()
                    # Verify the upstream call succeeded (web -> api via Consul mesh)
                    upstream = body.get("upstream")
                    if upstream and upstream.get("status") != 200:
                        resp.failure(
                            f"Upstream returned {upstream.get('status')}: "
                            f"{upstream.get('body', '')[:200]}"
                        )
                except json.JSONDecodeError:
                    resp.failure("Response is not valid JSON")
            else:
                resp.failure(f"Unexpected status {resp.status_code}")

    @task(2)
    def health_check(self):
        """GET /health — lightweight probe, should always be fast."""
        with self.client.get("/health", catch_response=True) as resp:
            if resp.status_code == 200:
                body = resp.json()
                if body.get("status") != "healthy":
                    resp.failure(f"Unhealthy: {body}")
            else:
                resp.failure(f"Health check returned {resp.status_code}")

    @task(1)
    def readiness_check(self):
        """GET /ready — readiness probe."""
        with self.client.get("/ready", catch_response=True) as resp:
            if resp.status_code == 200:
                body = resp.json()
                if body.get("status") != "ready":
                    resp.failure(f"Not ready: {body}")
            else:
                resp.failure(f"Readiness check returned {resp.status_code}")


class HighThroughputUser(HttpUser):
    """
    Aggressive user class for stress testing.  Minimal wait time to
    saturate pods and trigger HPA scale-out.
    """

    wait_time = between(0.1, 0.5)
    weight = 1  # lower weight — spawned less often than NetlixUser (weight=1 default)

    @task
    def rapid_homepage(self):
        """Rapid-fire homepage requests to drive CPU utilisation up."""
        self.client.get("/")


# ---------------------------------------------------------------------------
# Event hooks — log summary at the end of a headless run
# ---------------------------------------------------------------------------

@events.quitting.add_listener
def on_quitting(environment, **kwargs):
    """Print a summary and set exit code based on thresholds."""
    stats = environment.runner.stats
    total = stats.total

    if total.num_requests == 0:
        logger.error("No requests were made — check the target host")
        environment.process_exit_code = 2
        return

    fail_ratio = total.num_failures / total.num_requests
    p95 = total.get_response_time_percentile(0.95) or 0
    p99 = total.get_response_time_percentile(0.99) or 0

    logger.info("=" * 60)
    logger.info("LOAD TEST SUMMARY")
    logger.info("=" * 60)
    logger.info(f"  Total requests : {total.num_requests}")
    logger.info(f"  Failures       : {total.num_failures} ({fail_ratio:.2%})")
    logger.info(f"  Avg latency    : {total.avg_response_time:.0f} ms")
    logger.info(f"  p95 latency    : {p95:.0f} ms")
    logger.info(f"  p99 latency    : {p99:.0f} ms")
    logger.info(f"  Requests/sec   : {total.total_rps:.1f}")
    logger.info("=" * 60)

    # Thresholds — configurable via environment variables in the workflow
    import os
    max_fail_ratio = float(os.getenv("LOCUST_MAX_FAIL_RATIO", "0.05"))
    max_p95_ms = float(os.getenv("LOCUST_MAX_P95_MS", "2000"))

    failed = False
    if fail_ratio > max_fail_ratio:
        logger.error(
            f"FAIL: Error rate {fail_ratio:.2%} exceeds threshold {max_fail_ratio:.2%}"
        )
        failed = True
    if p95 > max_p95_ms:
        logger.error(
            f"FAIL: p95 latency {p95:.0f}ms exceeds threshold {max_p95_ms:.0f}ms"
        )
        failed = True

    if failed:
        environment.process_exit_code = 1
    else:
        logger.info("PASS: All thresholds met")
