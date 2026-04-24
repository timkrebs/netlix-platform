"""
Netlix Shop — Load Test Scenarios

Distributed Locust load tests targeting the shop (SPA + API) behind the
gateway. Exercises the real user flows from the Terminal frontend so the
test reflects actual production traffic shape:

  * Anonymous browsing (the bulk of visits) — catalog list + PDP fetches,
    plus SPA HTML requests for /, /p/:id, /cart (all the same index.html).
  * Authenticated shoppers — signup, /me validation, list+view products,
    place orders, list orders.
  * Health probes — continuous /health hits to surface liveness regressions.

Full request path: ALB -> gateway -> (SPA static | reverse proxy to
auth/catalog/orders via Consul service discovery).

Tunables (env vars):
  LOCUST_MAX_FAIL_RATIO  default 0.05   hard-fail threshold for error rate
  LOCUST_MAX_P95_MS      default 2000   hard-fail threshold for p95 latency
  LOCUST_EMAIL_DOMAIN    default loadtest.netlix.dev

Usage (headless CI):
  locust --headless -u 200 -r 10 --run-time 5m \
         --host https://app.dev.netlix.dev \
         --csv results/load-test
"""

import json
import logging
import os
import random
import time
import uuid

from locust import HttpUser, between, events, task

logger = logging.getLogger(__name__)

# Meets the auth service rule: 10+ chars, at least 3/4 of upper/lower/digit/symbol.
LOAD_PASSWORD = "LoadTest2025!Secure"
EMAIL_DOMAIN = os.getenv("LOCUST_EMAIL_DOMAIN", "loadtest.netlix.dev")


def unique_email():
    """Collision-resistant across workers: millisecond timestamp + 8 hex chars."""
    return f"lt-{int(time.time() * 1000)}-{uuid.uuid4().hex[:8]}@{EMAIL_DOMAIN}"


# ---------------------------------------------------------------------------
# CatalogBrowser — anonymous visitor, read-heavy. Most common traffic shape.
# ---------------------------------------------------------------------------
class CatalogBrowser(HttpUser):
    """Browses the catalog + PDPs without signing in. ~80% of simulated users."""

    wait_time = between(1, 3)
    weight = 8

    def on_start(self):
        self.product_ids = []
        self._seed_catalog()

    def _seed_catalog(self):
        with self.client.get(
            "/api/catalog/products",
            catch_response=True,
            name="/api/catalog/products [seed]",
        ) as resp:
            if resp.status_code == 200:
                try:
                    rows = resp.json()
                    self.product_ids = [p["id"] for p in rows]
                    resp.success()
                except (ValueError, KeyError):
                    resp.failure("Malformed product list")
            else:
                resp.failure(f"Seed fetch returned {resp.status_code}")

    @task(10)
    def list_products(self):
        self.client.get("/api/catalog/products", name="/api/catalog/products")

    @task(6)
    def view_product(self):
        if not self.product_ids:
            return
        pid = random.choice(self.product_ids)
        self.client.get(
            f"/api/catalog/products/{pid}",
            name="/api/catalog/products/:id",
        )

    @task(3)
    def spa_home(self):
        """SPA static HTML — hits the gateway's static handler, not a backend."""
        self.client.get("/", name="/ (SPA)")

    @task(2)
    def spa_pdp(self):
        if not self.product_ids:
            self.client.get("/", name="/ (SPA)")
            return
        pid = random.choice(self.product_ids)
        self.client.get(f"/p/{pid}", name="/p/:id (SPA)")


# ---------------------------------------------------------------------------
# Shopper — authenticated flow: signup → browse → order → list orders.
# ---------------------------------------------------------------------------
class Shopper(HttpUser):
    """Full conversion flow. ~20% of simulated users."""

    wait_time = between(2, 5)
    weight = 2

    def on_start(self):
        self.token = None
        self.product_ids = []
        self.orderable_product_ids = []
        self._signup_or_login()
        self._seed_catalog()

    def _signup_or_login(self):
        email = unique_email()
        body = {"email": email, "password": LOAD_PASSWORD}
        with self.client.post(
            "/api/auth/signup",
            json=body,
            catch_response=True,
            name="/api/auth/signup",
        ) as resp:
            if resp.status_code in (200, 201):
                try:
                    self.token = resp.json().get("token")
                    resp.success()
                except ValueError:
                    resp.failure("Signup response not JSON")
                    return
            elif resp.status_code == 409:
                # Extremely rare collision — fall back to login.
                resp.success()
                self._login_fallback(body)
            else:
                resp.failure(f"Signup returned {resp.status_code}")

    def _login_fallback(self, body):
        with self.client.post(
            "/api/auth/login",
            json=body,
            catch_response=True,
            name="/api/auth/login [fallback]",
        ) as resp:
            if resp.status_code == 200:
                try:
                    self.token = resp.json().get("token")
                    resp.success()
                except ValueError:
                    resp.failure("Login response not JSON")
            else:
                resp.failure(f"Login fallback returned {resp.status_code}")

    def _seed_catalog(self):
        with self.client.get(
            "/api/catalog/products",
            catch_response=True,
            name="/api/catalog/products [seed]",
        ) as resp:
            if resp.status_code == 200:
                try:
                    rows = resp.json()
                    self.product_ids = [p["id"] for p in rows]
                    self.orderable_product_ids = [
                        p["id"] for p in rows if p.get("stock", 0) > 0
                    ]
                    resp.success()
                except (ValueError, KeyError):
                    resp.failure("Malformed product list")

    def _auth_headers(self):
        return {"Authorization": f"Bearer {self.token}"} if self.token else {}

    @task(8)
    def list_products(self):
        self.client.get("/api/catalog/products", name="/api/catalog/products")

    @task(5)
    def view_product(self):
        if not self.product_ids:
            return
        pid = random.choice(self.product_ids)
        self.client.get(
            f"/api/catalog/products/{pid}",
            name="/api/catalog/products/:id",
        )

    @task(2)
    def validate_session(self):
        if not self.token:
            return
        with self.client.get(
            "/api/auth/me",
            headers=self._auth_headers(),
            catch_response=True,
            name="/api/auth/me",
        ) as resp:
            if resp.status_code == 200:
                resp.success()
            elif resp.status_code == 401:
                # Session expired mid-test — re-auth and retry next tick.
                self.token = None
                resp.success()
                self._signup_or_login()
            else:
                resp.failure(f"/me returned {resp.status_code}")

    @task(2)
    def view_orders(self):
        if not self.token:
            return
        self.client.get(
            "/api/orders/orders",
            headers=self._auth_headers(),
            name="/api/orders/orders",
        )

    @task(1)
    def place_order(self):
        if not self.token or not self.orderable_product_ids:
            return
        pick_count = min(random.randint(1, 3), len(self.orderable_product_ids))
        items = [
            {"product_id": pid, "quantity": random.randint(1, 2)}
            for pid in random.sample(self.orderable_product_ids, k=pick_count)
        ]
        with self.client.post(
            "/api/orders/orders",
            json={"items": items},
            headers=self._auth_headers(),
            catch_response=True,
            name="/api/orders/orders [create]",
        ) as resp:
            if resp.status_code in (200, 201):
                resp.success()
            elif resp.status_code in (400, 409, 422):
                # Stock depletion or validation — expected under sustained load.
                # Not a load-test failure; note and move on.
                logger.debug("Order rejected: %s %s", resp.status_code, resp.text[:120])
                resp.success()
            elif resp.status_code == 401:
                # Token aged out — re-auth next tick.
                self.token = None
                resp.failure("Token rejected mid-session")
            else:
                resp.failure(f"Order create returned {resp.status_code}")


# ---------------------------------------------------------------------------
# HealthProbe — liveness probes at probe-like cadence.
# ---------------------------------------------------------------------------
class HealthProbe(HttpUser):
    """Lightweight probes. Matches k8s liveness cadence."""

    wait_time = between(1, 2)
    weight = 1

    @task
    def health(self):
        with self.client.get(
            "/health", catch_response=True, name="/health"
        ) as resp:
            if resp.status_code == 200:
                try:
                    body = resp.json()
                    if body.get("status") not in ("healthy", "ok", "up", None):
                        resp.failure(f"Unhealthy body: {body}")
                    else:
                        resp.success()
                except (ValueError, json.JSONDecodeError):
                    # Some health endpoints return "OK\n" plain text — still healthy.
                    resp.success()
            else:
                resp.failure(f"/health returned {resp.status_code}")


# ---------------------------------------------------------------------------
# Event hooks — log summary at the end of a headless run.
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

    # Per-endpoint breakdown — makes it easy to spot which flow degraded.
    logger.info("PER-ENDPOINT BREAKDOWN")
    logger.info("-" * 60)
    for name, entry in sorted(stats.entries.items()):
        if entry.num_requests == 0:
            continue
        entry_p95 = entry.get_response_time_percentile(0.95) or 0
        entry_fail_ratio = (
            entry.num_failures / entry.num_requests if entry.num_requests else 0
        )
        logger.info(
            f"  {name[0]:<35} {entry.num_requests:>7} req  "
            f"p95={entry_p95:>5.0f}ms  fail={entry_fail_ratio:.1%}"
        )
    logger.info("=" * 60)

    # Thresholds — configurable via environment variables in the workflow
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
