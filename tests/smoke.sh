#!/usr/bin/env bash
#
# DIGGER smoke tests - non-interactive regression harness.
#
#   bash tests/smoke.sh
#
# Every module that exists is exercised in CLI mode (no prompts) so the
# suite is safe to run in CI. A module that prints an error but exits 0
# counts as a failure, not a pass.
#
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIGGER="${ROOT}/digger.sh"

PASS=0
FAIL=0
SKIP=0
OUT=""
RC=0

if [[ -t 1 ]]; then
  G=$'\033[32m'; R=$'\033[31m'; Y=$'\033[33m'; D=$'\033[2m'; N=$'\033[0m'
else
  G=''; R=''; Y=''; D=''; N=''
fi

c_pass() { printf '  %sPASS%s  %s\n' "$G" "$N" "$1"; PASS=$((PASS + 1)); }
c_fail() { printf '  %sFAIL%s  %s\n' "$R" "$N" "$1"; FAIL=$((FAIL + 1)); }
c_skip() { printf '  %sSKIP%s  %s\n' "$Y" "$N" "$1"; SKIP=$((SKIP + 1)); }

run() {
  OUT="$(bash "$DIGGER" "$@" 2>&1)"
  RC=$?
}

expect_match() {
  local name="$1" pattern="$2"
  if printf '%s' "$OUT" | grep -Eq "$pattern"; then
    c_pass "$name"
  else
    c_fail "$name"
    printf '        expected pattern: %s\n' "$pattern"
    printf '        got: %s\n' "$(printf '%s' "$OUT" | head -n 4 | tr '\n' '|')"
  fi
}

expect_status() {
  local name="$1" want="$2"
  if [[ "$RC" == "$want" ]]; then
    c_pass "$name"
  else
    c_fail "$name"
    printf '        expected exit status %s, got %s\n' "$want" "$RC"
    printf '        got: %s\n' "$(printf '%s' "$OUT" | head -n 4 | tr '\n' '|')"
  fi
}

section() { printf '\n%s== %s ==%s\n' "$D" "$1" "$N"; }

# ---------------------------------------------------------------------------
section "core"

run --version
expect_match "version prints tool name" 'DIGGER'
expect_match "version prints semver" '[0-9]+\.[0-9]+\.[0-9]+'
expect_status "version exits 0" 0

run --help
expect_match "help lists usage" 'USAGE'
expect_match "help lists commands" 'COMMANDS'
expect_status "help exits 0" 0

run bogus-command-xyz
expect_match "unknown command is reported" 'unknown command'
expect_status "unknown command exits 1" 1

run --no-color --version
expect_status "no-color version exits 0" 0

# ---------------------------------------------------------------------------
section "module: myip"

run myip
expect_match "myip prints a public IPv4" '([0-9]{1,3}\.){3}[0-9]{1,3}'
expect_match "myip prints location block" 'Country'
expect_status "myip exits 0" 0

# ---------------------------------------------------------------------------
section "module: dns"

if command -v dig >/dev/null 2>&1; then
  run dns example.com
  expect_match "dns returns records for example.com" 'example\.com'
  expect_status "dns exits 0" 0

  run dns
  expect_match "dns without target prompts then fails cleanly" 'no target|invalid target'
else
  c_skip "dns tests (dig not installed)"
fi

run dns 'not a hostname!!'
expect_match "dns rejects garbage target" 'invalid target'

# ---------------------------------------------------------------------------
section "module: stubs"

for m in info scan hosts domain links subdomains archive paths tls cdn intel secrets dorks social net; do
  run "$m" some-target
  expect_match "stub '$m' reports not implemented" 'not implemented yet'
done

# ---------------------------------------------------------------------------
printf '\n%s%d passed%s, %s%d failed%s, %s%d skipped%s\n' \
  "$G" "$PASS" "$N" "$R" "$FAIL" "$N" "$Y" "$SKIP" "$N"

(( FAIL == 0 )) || exit 1
exit 0
