#!/usr/bin/env bash
#
# check-results.sh — Validate Locust CSV results against thresholds.
#
# Usage:
#   ./check-results.sh <results_prefix>
#
# Expects Locust CSV output files:
#   <prefix>_stats.csv        — per-endpoint stats
#   <prefix>_stats_history.csv — time-series data
#   <prefix>_failures.csv     — failure details
#
# Environment variables (thresholds):
#   MAX_FAIL_RATIO   — max failure ratio (default: 0.05 = 5%)
#   MAX_P95_MS       — max p95 response time in ms (default: 2000)
#   MAX_AVG_MS       — max average response time in ms (default: 1000)
#   MIN_RPS          — minimum requests/sec (default: 10)

set -euo pipefail

PREFIX="${1:?Usage: check-results.sh <results_prefix>}"
STATS_FILE="${PREFIX}_stats.csv"

if [[ ! -f "$STATS_FILE" ]]; then
  echo "ERROR: Stats file not found: $STATS_FILE"
  exit 2
fi

# Defaults
MAX_FAIL_RATIO="${MAX_FAIL_RATIO:-0.05}"
MAX_P95_MS="${MAX_P95_MS:-2000}"
MAX_AVG_MS="${MAX_AVG_MS:-1000}"
MIN_RPS="${MIN_RPS:-10}"

echo "============================================================"
echo "LOAD TEST RESULTS VALIDATION"
echo "============================================================"
echo ""
echo "Thresholds:"
echo "  Max failure ratio : ${MAX_FAIL_RATIO}"
echo "  Max p95 latency   : ${MAX_P95_MS} ms"
echo "  Max avg latency   : ${MAX_AVG_MS} ms"
echo "  Min requests/sec  : ${MIN_RPS}"
echo ""

# Parse the "Aggregated" row from Locust CSV
# Locust may output the name quoted ("Aggregated") or unquoted (,Aggregated,)
# depending on the version, so we match both patterns.
#
# Columns: Type,Name,Request Count,Failure Count,Median Response Time,
#           Average Response Time,Min Response Time,Max Response Time,
#           Average Content Size,Requests/s,Failures/s,
#           50%,66%,75%,80%,90%,95%,98%,99%,99.9%,99.99%,100%
AGGREGATED=$(grep -i 'Aggregated' "$STATS_FILE" | grep -v '^Type' || true)

if [[ -z "$AGGREGATED" ]]; then
  echo "ERROR: No 'Aggregated' row found in $STATS_FILE"
  echo "Contents:"
  cat "$STATS_FILE"
  exit 2
fi

# Strip any double quotes so field parsing is consistent
AGGREGATED=$(echo "$AGGREGATED" | tr -d '"')

# Extract fields (comma-separated, quotes stripped)
REQUEST_COUNT=$(echo "$AGGREGATED" | awk -F',' '{print $3}')
FAILURE_COUNT=$(echo "$AGGREGATED" | awk -F',' '{print $4}')
AVG_MS=$(echo "$AGGREGATED" | awk -F',' '{print $6}')
RPS=$(echo "$AGGREGATED" | awk -F',' '{print $10}')
P95_MS=$(echo "$AGGREGATED" | awk -F',' '{print $17}')

echo "Results:"
echo "  Total requests    : ${REQUEST_COUNT}"
echo "  Failures          : ${FAILURE_COUNT}"
echo "  Average latency   : ${AVG_MS} ms"
echo "  p95 latency       : ${P95_MS} ms"
echo "  Requests/sec      : ${RPS}"
echo ""

FAILED=0

# Check failure ratio
if [[ "$REQUEST_COUNT" -gt 0 ]]; then
  FAIL_RATIO=$(awk "BEGIN {printf \"%.4f\", ${FAILURE_COUNT}/${REQUEST_COUNT}}")
  echo "  Failure ratio     : ${FAIL_RATIO}"
  if awk "BEGIN {exit !(${FAIL_RATIO} > ${MAX_FAIL_RATIO})}"; then
    echo "  FAIL: Error rate ${FAIL_RATIO} exceeds ${MAX_FAIL_RATIO}"
    FAILED=1
  fi
else
  echo "  FAIL: No requests were made"
  FAILED=1
fi

# Check p95
if awk "BEGIN {exit !(${P95_MS} > ${MAX_P95_MS})}"; then
  echo "  FAIL: p95 ${P95_MS}ms exceeds ${MAX_P95_MS}ms"
  FAILED=1
fi

# Check avg
if awk "BEGIN {exit !(${AVG_MS} > ${MAX_AVG_MS})}"; then
  echo "  FAIL: avg ${AVG_MS}ms exceeds ${MAX_AVG_MS}ms"
  FAILED=1
fi

# Check RPS
if awk "BEGIN {exit !(${RPS} < ${MIN_RPS})}"; then
  echo "  FAIL: RPS ${RPS} below minimum ${MIN_RPS}"
  FAILED=1
fi

echo ""
echo "============================================================"
if [[ "$FAILED" -eq 1 ]]; then
  echo "RESULT: FAILED — thresholds exceeded"
  exit 1
else
  echo "RESULT: PASSED — all thresholds met"
  exit 0
fi
