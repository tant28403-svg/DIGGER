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
section "module: info (IP)"

run info 8.8.8.8
expect_match "info reports location for an IP" 'Location|Country'
expect_match "info reports allocation data" 'Allocation|RDAP|Net name'
expect_status "info on an IP exits 0" 0

# ---------------------------------------------------------------------------
section "module: info (site)"

run info example.com
expect_match "info reports HTTP status for a site" 'Status'
expect_match "info reports a title" 'Title'
expect_match "info audits security headers" 'Security headers'
expect_status "info on a site exits 0" 0

# ---------------------------------------------------------------------------
section "module: domain"

run domain example.com
expect_match "domain reports registration" 'Registration|Whois'
expect_match "domain reports events or dates" 'Events|Creation|Expiry|Status'
expect_status "domain exits 0" 0

run domain 'not a domain!!'
expect_match "domain rejects garbage" 'invalid domain'

# ---------------------------------------------------------------------------
section "module: links"

run links http://example.com --depth 1 --max-pages 5 --delay 0
expect_match "links reports a crawl summary" 'Pages crawled'
expect_match "links reports the target" 'example\.com'
expect_status "links exits 0" 0

run links 'not a url at all!!'
expect_match "links rejects garbage" 'no URL given|invalid'

# ---------------------------------------------------------------------------
section "module: paths"

run paths https://example.com -y --wordlist "${ROOT}/tests/fixtures/paths-mini.txt" --concurrency 5 --timeout 10
expect_match "paths reports a wordlist" 'Wordlist'
expect_match "paths reports results" 'Results|Probed'
expect_status "paths exits 0" 0

run paths 'not a url at all!!'
expect_match "paths rejects garbage" 'invalid target'

# ---------------------------------------------------------------------------
section "module: tls"

run tls example.com
expect_match "tls reports the negotiated protocol" 'Protocol'
expect_match "tls reports certificate details" 'Certificate|Subject'
expect_match "tls reports protocol support" 'Protocol support'
expect_status "tls exits 0" 0

run tls 'not a host!!'
expect_match "tls rejects garbage" 'invalid host'

# ---------------------------------------------------------------------------
section "module: cdn"

run cdn example.com
expect_match "cdn reports detection" 'Detection'
expect_match "cdn reports resolution" 'ASN|IP address'
expect_status "cdn exits 0" 0

run cdn 'not a host!!'
expect_match "cdn rejects garbage" 'invalid host'

# ---------------------------------------------------------------------------
section "module: intel"

run intel 8.8.8.8
expect_match "intel reports DNS blacklists" 'DNS blacklists'
expect_match "intel reports IP blacklists" 'IP blacklists'
expect_match "intel prints a summary" 'Summary'
expect_status "intel exits 0" 0

run intel 'not a target!!'
expect_match "intel rejects garbage" 'invalid target'

# ---------------------------------------------------------------------------
section "module: subdomains"

run subdomains 'not a domain!!'
expect_match "subdomains rejects garbage" 'invalid domain'

run subdomains example.com --no-ct --no-pdns --no-wordlist --no-pattern
expect_match "subdomains lists its sources" 'Sources'
expect_match "subdomains reports candidates" 'Candidates'
expect_match "subdomains prints a summary" 'Summary'
expect_status "subdomains with everything disabled exits 0" 0

run subdomains example.com --no-ct --no-pdns --limit 3
expect_match "subdomains resolves a wordlist sample" 'resolving [0-9]+ names'
expect_match "subdomains reports confidence tiers" 'CONFIDENCE|Results'
expect_status "subdomains wordlist run exits 0" 0

run subdomains example.com --no-wordlist --no-pattern --no-resolve
expect_match "subdomains queries the passive sources" 'passive sources'
expect_status "subdomains passive run exits 0" 0

# ---------------------------------------------------------------------------
section "module: hosts"

run hosts 'not a host!!'
expect_match "hosts rejects garbage" 'invalid target'

run hosts example.com
expect_match "hosts prints forward records" 'Forward'
expect_match "hosts prints reverse hosts" 'Reverse hosts'
expect_match "hosts prints a summary" 'Summary'
expect_status "hosts passive run exits 0" 0

run hosts example.com --vhosts --limit 1
expect_match "hosts skips probing without consent" 'vhost probing skipped'
expect_status "hosts refuses active probing non-interactively" 0

run hosts --help
expect_match "hosts has its own usage" 'digger.sh hosts'

# ---------------------------------------------------------------------------
section "module: scan"

run scan 'bad host!!'
expect_match "scan rejects garbage" 'invalid target'

run scan example.com
expect_match "scan asks before probing" 'aborted'
expect_status "scan refuses to probe without consent" 0

run scan example.com --ports 443 -y
expect_match "scan reports results" 'Results'
expect_match "scan prints a summary" 'Summary'
expect_status "scan runs with --yes" 0

run scan --help
expect_match "scan has its own usage" 'digger.sh scan'

# ---------------------------------------------------------------------------
section "module: stubs"

for m in archive secrets dorks social net; do
  run "$m" some-target
  expect_match "stub '$m' reports not implemented" 'not implemented yet'
done

# ---------------------------------------------------------------------------
printf '\n%s%d passed%s, %s%d failed%s, %s%d skipped%s\n' \
  "$G" "$PASS" "$N" "$R" "$FAIL" "$N" "$Y" "$SKIP" "$N"

(( FAIL == 0 )) || exit 1
exit 0
