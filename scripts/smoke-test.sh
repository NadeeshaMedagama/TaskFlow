#!/usr/bin/env bash
#
# smoke-test.sh -- bring the TaskFlow stack up, wait for every service to
# report healthy, exercise the API end to end, and report pass/fail.
#
# Exits 0 only if every check passed, so it works unchanged as a CI gate.
#
# Usage:
#   scripts/smoke-test.sh                # prod-like: base compose file only
#   scripts/smoke-test.sh --dev          # include docker-compose.override.yml
#   scripts/smoke-test.sh --no-build     # reuse existing images
#   scripts/smoke-test.sh --down         # tear the stack down when finished
#
# Environment:
#   BASE_URL   where the web tier is published   (default http://localhost:8080)
#   TIMEOUT    seconds to wait for health        (default 180)

set -euo pipefail

# Run from the project root regardless of where this was invoked from, so the
# relative compose paths and build contexts resolve.
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
cd -- "$SCRIPT_DIR/.."

BASE_URL=${BASE_URL:-http://localhost:8080}
TIMEOUT=${TIMEOUT:-180}
SERVICES=(taskflow-db taskflow-cache taskflow-api taskflow-web)

COMPOSE_FILES=(-f docker-compose.yml)
DO_BUILD=1
DO_DOWN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dev)      COMPOSE_FILES=(-f docker-compose.yml -f docker-compose.override.yml) ;;
    --no-build) DO_BUILD=0 ;;
    --down)     DO_DOWN=1 ;;
    -h|--help)  sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)          echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

if [[ -t 1 ]]; then
  RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; BOLD=$'\033[1m'; DIM=$'\033[2m'; RESET=$'\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BOLD=''; DIM=''; RESET=''
fi

PASSED=0
FAILED=0

TMPDIR_=$(mktemp -d)
BODY="$TMPDIR_/body"
trap 'rm -rf "$TMPDIR_"' EXIT

step() { printf '\n%s==> %s%s\n' "$BOLD" "$1" "$RESET"; }
pass() { printf '  %s✓%s %s\n' "$GREEN" "$RESET" "$1"; PASSED=$((PASSED + 1)); }
fail() { printf '  %s✗%s %s\n' "$RED" "$RESET" "$1"; FAILED=$((FAILED + 1)); }
note() { printf '  %s%s%s\n' "$DIM" "$1" "$RESET"; }

compose() { docker compose "${COMPOSE_FILES[@]}" "$@"; }

# ---------------------------------------------------------------------------

step "Preflight"

if ! docker version --format '{{.Server.Version}}' >/dev/null 2>&1; then
  printf '  %s✗%s Docker daemon is not reachable. Start Docker Desktop and retry.\n' "$RED" "$RESET"
  exit 1
fi
pass "Docker daemon reachable"

if ! docker compose version >/dev/null 2>&1; then
  printf '  %s✗%s Docker Compose v2 not found (`docker compose version` failed).\n' "$RED" "$RESET"
  exit 1
fi
pass "Docker Compose v2 available"

if [[ ! -f .env ]]; then
  printf '  %s✗%s .env is missing. Run: cp .env.example .env\n' "$RED" "$RESET"
  exit 1
fi
pass ".env present"

# ---------------------------------------------------------------------------

step "Starting the stack"
note "compose files:${COMPOSE_FILES[*]}"

if (( DO_BUILD )); then
  compose up -d --build
else
  compose up -d
fi

# ---------------------------------------------------------------------------

step "Waiting for health (timeout ${TIMEOUT}s)"

wait_healthy() {
  # Named `state`, not `status`: `status` is a read-only special variable in
  # zsh, so the function would break outright for anyone running this with
  # `zsh scripts/smoke-test.sh` instead of executing it via the shebang.
  local svc=$1 deadline=$((SECONDS + TIMEOUT)) cid state
  while (( SECONDS < deadline )); do
    cid=$(compose ps -q "$svc" 2>/dev/null || true)
    if [[ -n "$cid" ]]; then
      # Falls back to State.Status for any service without a healthcheck.
      state=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$cid" 2>/dev/null || echo unknown)
      case "$state" in
        healthy|running) return 0 ;;
        exited|dead)     return 1 ;;
      esac
    fi
    sleep 2
  done
  return 1
}

health_ok=1
for svc in "${SERVICES[@]}"; do
  if wait_healthy "$svc"; then
    pass "$svc is healthy"
  else
    fail "$svc never became healthy"
    health_ok=0
  fi
done

if (( ! health_ok )); then
  step "Recent logs"
  compose logs --tail=40 || true
  printf '\n%sFAILED%s: the stack did not come up.\n' "$RED$BOLD" "$RESET"
  exit 1
fi

# ---------------------------------------------------------------------------

step "Exercising the API at $BASE_URL"

http() {
  local method=$1 url=$2 data=${3:-}
  local args=(-sS -o "$BODY" -w '%{http_code}' -X "$method" --max-time 10)
  [[ -n "$data" ]] && args+=(-H 'Content-Type: application/json' -d "$data")
  curl ${args[@]+"${args[@]}"} "$url" 2>/dev/null || echo 000
}

# 1. Liveness through the nginx proxy.
code=$(http GET "$BASE_URL/health")
if [[ "$code" == 200 ]] && grep -q '"status":"ok"' "$BODY"; then
  pass "GET /health -> 200 {\"status\":\"ok\"}"
else
  fail "GET /health -> $code $(head -c 120 "$BODY")"
fi

# 2. Read the seeded list.
code=$(http GET "$BASE_URL/api/tasks")
if [[ "$code" == 200 ]] && grep -q '"tasks"' "$BODY"; then
  pass "GET /api/tasks -> 200, body has a tasks array"
else
  fail "GET /api/tasks -> $code $(head -c 120 "$BODY")"
fi

# 3. Create one, with a unique title so we can find it again.
TITLE="smoke-test-$(date +%s)-$$"
code=$(http POST "$BASE_URL/api/tasks" "{\"title\":\"$TITLE\",\"description\":\"created by smoke-test.sh\"}")
if [[ "$code" == 201 ]] && grep -q "\"title\":\"$TITLE\"" "$BODY"; then
  pass "POST /api/tasks -> 201, echoes the created task"
else
  fail "POST /api/tasks -> $code $(head -c 120 "$BODY")"
fi

# 4. The POST deletes the cache key, so this read must come from the database
#    and must contain what we just wrote.
code=$(http GET "$BASE_URL/api/tasks")
if [[ "$code" == 200 ]] && grep -q "\"title\":\"$TITLE\"" "$BODY"; then
  pass "GET /api/tasks -> the new task is present"
else
  fail "GET /api/tasks -> new task missing (code $code)"
fi

if grep -q '"source":"db"' "$BODY"; then
  pass "cache was invalidated by the POST (source=db)"
else
  fail "expected source=db after a write, got $(grep -o '\"source\":\"[a-z]*\"' "$BODY" || echo '?')"
fi

# 5. That read repopulated the cache, so the next one must be served from it.
code=$(http GET "$BASE_URL/api/tasks")
if grep -q '"source":"cache"' "$BODY"; then
  pass "repeat read served from Redis (source=cache)"
else
  fail "expected source=cache on the repeat read, got $(grep -o '\"source\":\"[a-z]*\"' "$BODY" || echo '?')"
fi

# ---------------------------------------------------------------------------

step "Result"

printf '  %s%d passed%s, %s%d failed%s\n' "$GREEN" "$PASSED" "$RESET" \
  "$([[ $FAILED -gt 0 ]] && echo "$RED" || echo "$DIM")" "$FAILED" "$RESET"

if (( DO_DOWN )); then
  note "tearing the stack down (--down); the named volume is kept"
  compose down
else
  note "stack left running -- 'docker compose down' to stop it"
fi

if (( FAILED > 0 )); then
  printf '\n%sSMOKE TEST FAILED%s\n' "$RED$BOLD" "$RESET"
  printf '%sInspect with: docker compose logs -f%s\n' "$DIM" "$RESET"
  exit 1
fi

printf '\n%sSMOKE TEST PASSED%s\n' "$GREEN$BOLD" "$RESET"
