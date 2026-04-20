#!/usr/bin/env bash
# End-to-end smoke test against the docker-compose stack.
#
#   docker compose -f app/services/docker-compose.yml up --build -d
#   ./app/services/smoke-test.sh
#
# Exits 0 if every step succeeds, non-zero otherwise.

set -euo pipefail

GATEWAY="${GATEWAY:-http://localhost:8080}"
EMAIL="smoke-$(date +%s)@netlix.dev"
PASSWORD="SmokeTest12!Pass"

red()   { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
step()  { printf '\n\033[36m▶ %s\033[0m\n' "$*"; }

require() {
  if ! command -v "$1" >/dev/null; then
    red "missing tool: $1"; exit 1
  fi
}
require curl
require jq

step "wait for gateway to be ready"
for i in $(seq 1 60); do
  if curl -fsS "$GATEWAY/health" >/dev/null 2>&1; then
    green "gateway is up"
    break
  fi
  if [[ $i -eq 60 ]]; then red "gateway never came up"; exit 1; fi
  sleep 1
done

step "list products via gateway → catalog"
PRODUCTS=$(curl -fsS "$GATEWAY/api/catalog/products")
COUNT=$(echo "$PRODUCTS" | jq 'length')
if [[ "$COUNT" -lt 1 ]]; then red "expected ≥1 product, got $COUNT"; exit 1; fi
green "got $COUNT products"

PRODUCT_ID=$(echo "$PRODUCTS" | jq '.[0].id')
PRODUCT_PRICE=$(echo "$PRODUCTS" | jq '.[0].price_cents')

step "fetch single product /products/$PRODUCT_ID"
curl -fsS "$GATEWAY/api/catalog/products/$PRODUCT_ID" | jq -e ".id == $PRODUCT_ID" >/dev/null
green "single-product fetch ok"

step "signup new user $EMAIL"
SIGNUP=$(curl -fsS -X POST "$GATEWAY/api/auth/signup" \
  -H 'Content-Type: application/json' \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}")
TOKEN=$(echo "$SIGNUP" | jq -r '.token')
USER_ID=$(echo "$SIGNUP" | jq -r '.user_id')
if [[ -z "$TOKEN" || "$TOKEN" == "null" ]]; then red "no token in signup response"; exit 1; fi
green "signed up user_id=$USER_ID"

step "duplicate signup should fail with 409"
HTTP=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$GATEWAY/api/auth/signup" \
  -H 'Content-Type: application/json' \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}")
if [[ "$HTTP" != "409" ]]; then red "expected 409, got $HTTP"; exit 1; fi
green "duplicate-signup rejected (409)"

step "login again should succeed"
LOGIN=$(curl -fsS -X POST "$GATEWAY/api/auth/login" \
  -H 'Content-Type: application/json' \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}")
TOKEN=$(echo "$LOGIN" | jq -r '.token')
green "login ok"

step "place order without token should fail with 401"
HTTP=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$GATEWAY/api/orders/orders" \
  -H 'Content-Type: application/json' \
  -d "{\"items\":[{\"product_id\":$PRODUCT_ID,\"quantity\":1}]}")
if [[ "$HTTP" != "401" ]]; then red "expected 401, got $HTTP"; exit 1; fi
green "unauthenticated order rejected (401)"

step "place order with token"
ORDER=$(curl -fsS -X POST "$GATEWAY/api/orders/orders" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $TOKEN" \
  -d "{\"items\":[{\"product_id\":$PRODUCT_ID,\"quantity\":2}]}")
ORDER_ID=$(echo "$ORDER" | jq -r '.id')
ORDER_TOTAL=$(echo "$ORDER" | jq -r '.total_cents')
EXPECTED=$((PRODUCT_PRICE * 2))
if [[ "$ORDER_TOTAL" != "$EXPECTED" ]]; then
  red "wrong total: got $ORDER_TOTAL want $EXPECTED"; exit 1
fi
green "order #$ORDER_ID placed, total=$ORDER_TOTAL"

step "list orders for user"
ORDERS=$(curl -fsS "$GATEWAY/api/orders/orders" -H "Authorization: Bearer $TOKEN")
N=$(echo "$ORDERS" | jq 'length')
if [[ "$N" -lt 1 ]]; then red "expected ≥1 order, got $N"; exit 1; fi
green "user has $N order(s)"

step "GET /me returns the user profile"
ME=$(curl -fsS "$GATEWAY/api/auth/me" -H "Authorization: Bearer $TOKEN")
ME_EMAIL=$(echo "$ME" | jq -r '.email')
if [[ "$ME_EMAIL" != "$EMAIL" ]]; then red "wrong /me email: $ME_EMAIL"; exit 1; fi
green "/me returns $ME_EMAIL"

step "weak password rejected on signup"
HTTP=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$GATEWAY/api/auth/signup" \
  -H 'Content-Type: application/json' \
  -d '{"email":"weak-'$(date +%s)'@netlix.dev","password":"weakpass"}')
if [[ "$HTTP" != "400" ]]; then red "expected 400 on weak password, got $HTTP"; exit 1; fi
green "weak password rejected (400)"

step "logout revokes token"
curl -fsS -X POST "$GATEWAY/api/auth/logout" -H "Authorization: Bearer $TOKEN" >/dev/null
HTTP=$(curl -s -o /dev/null -w '%{http_code}' "$GATEWAY/api/auth/me" -H "Authorization: Bearer $TOKEN")
if [[ "$HTTP" != "401" ]]; then red "expected 401 on revoked token, got $HTTP"; exit 1; fi
HTTP=$(curl -s -o /dev/null -w '%{http_code}' "$GATEWAY/api/orders/orders" -H "Authorization: Bearer $TOKEN")
if [[ "$HTTP" != "401" ]]; then red "expected 401 on orders with revoked token, got $HTTP"; exit 1; fi
green "revoked token rejected by both auth and orders"

step "fetch SPA index"
HTML=$(curl -fsS "$GATEWAY/")
if ! echo "$HTML" | grep -q '<div id="root">'; then
  red "SPA index missing #root"; exit 1
fi
green "SPA served"

green "\nALL SMOKE TESTS PASSED"
