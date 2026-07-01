#!/usr/bin/env bash
# /home/ubuntu/scripts/verify-assist.sh
# Smoke-test 5 endpoint penting di assist-bot. Exit 0 kalau semua OK,
# exit 1 kalau ada yg fail. Dipake sebelum & sesudah edit kode.
#
# Usage:
#   ./verify-assist.sh           # human-readable
#   ./verify-assist.sh --quiet   # CI mode: silent kecuali ada fail

set -u
QUIET=0
[ "${1:-}" = "--quiet" ] && QUIET=1

ENV_FILE="/home/ubuntu/assist-bot/.env"
SVR_TOKEN=$(grep -E '^SERVER_TOKEN=' "$ENV_FILE" 2>/dev/null | cut -d= -f2-)
BASE="http://localhost:3500"
AUTH="Authorization: Bearer $SVR_TOKEN"

PASS=0; FAIL=0

# Run a curl command, check output matches expected pattern.
# $1 = test name, $2 = expected regex, $3 = curl-assembled output already
check() {
  local name="$1"; local expect_pat="$2"; local out="$3"
  if echo "$out" | grep -qE "$expect_pat"; then
    [ $QUIET -eq 0 ] && echo "  ✅ $name"
    PASS=$((PASS+1))
  else
    echo "  ❌ $name"
    echo "     output: $(echo "$out" | head -c 200)"
    FAIL=$((FAIL+1))
  fi
}

[ $QUIET -eq 0 ] && echo "=== assist-bot smoke test ==="

# 1. /health (no auth)
out=$(curl -sS --max-time 10 "$BASE/health" 2>&1) || true
check "GET /health" '"ok"|"alive"|ok' "$out"

# 2. /accounts (GET, with auth) — list akun aktif
out=$(curl -sS --max-time 10 -H "$AUTH" "$BASE/accounts" 2>&1) || true
check "GET /accounts (need 1+ active)" 'H704|H705|dealer_code' "$out"

# 3. /lookup-engine: cached engine (must be fast, <5s if cached, <60s cold)
T0=$(date +%s%3N)
out=$(curl -sS --max-time 65 -H "$AUTH" -H "Content-Type: application/json" \
  -X POST -d '{"engineNo":"JMG1E1763781","format":"text"}' \
  "$BASE/lookup-engine" 2>&1) || true
T1=$(date +%s%3N)
check "POST /lookup-engine" 'H704-SPK|engine|found' "$out"
[ $QUIET -eq 0 ] && echo "     elapsed: $((T1-T0))ms"

# 4. /stock — basic stock fetch (multi-account: kasih dealer eksplisit)
out=$(curl -sS --max-time 30 -H "$AUTH" -H "Content-Type: application/json" \
  -X POST -d '{"dealer":"H704"}' "$BASE/stock" 2>&1) || true
check "POST /stock (H704)" 'stock|total|nodes|H704|H705' "$out"

# 5. systemd assist-bot active
if systemctl --user is-active --quiet assist-bot.service; then
  [ $QUIET -eq 0 ] && echo "  ✅ assist-bot.service active"
  PASS=$((PASS+1))
else
  echo "  ❌ assist-bot.service NOT active"
  FAIL=$((FAIL+1))
fi

[ $QUIET -eq 0 ] && echo "==="
[ $QUIET -eq 0 ] && echo "PASS: $PASS  FAIL: $FAIL"

if [ $FAIL -gt 0 ]; then exit 1; fi
exit 0
