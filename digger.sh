#!/usr/bin/env bash
#
# DIGGER v1.0 - passive first, loud when needed
#
# Reconnaissance toolkit for Linux. Single file, no build step, keyless
# data sources only.
#
#   ./digger.sh              interactive menu
#   ./digger.sh <command>    non-interactive
#
set -euo pipefail

readonly TOOL_NAME="DIGGER"
readonly VERSION="1.0.0"
readonly USER_AGENT="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36 DIGGER/${VERSION}"

# ---------------------------------------------------------------------------
# Globals
# ---------------------------------------------------------------------------
NO_COLOR="${NO_COLOR:-}"
SHOW_BANNER=1
ASSUME_YES="${ASSUME_YES:-}"
HTTP_TIMEOUT="${HTTP_TIMEOUT:-15}"
HTTP_RETRIES="${HTTP_RETRIES:-1}"
PY=""

DIGGER_HOME=""

# Locate the directory holding digger.sh so shipped wordlists are found no
# matter what the current working directory is. A symlinked install (the
# default for install.sh) is resolved to its real location first.
resolve_home() {
  local src="${BASH_SOURCE[0]}" dir target
  if have readlink; then
    for _ in 1 2 3 4 5 6 7 8; do
      [[ -L "$src" ]] || break
      target=$(readlink -- "$src" 2>/dev/null || true)
      [[ -z "$target" ]] && break
      if [[ "$target" != /* ]]; then
        target="$(cd -- "$(dirname -- "$src")" >/dev/null 2>&1 && pwd -P)/${target}"
      fi
      src="$target"
    done
  fi
  dir=$(cd -- "$(dirname -- "$src")" >/dev/null 2>&1 && pwd -P) || return 1
  DIGGER_HOME="$dir"
}

# Print the path to a shipped wordlist, or fail if it cannot be found.
wordlist_file() {
  local name="$1" p
  for p in "${DIGGER_HOME}/wordlist/${name}" "./wordlist/${name}" \
           "${HOME}/.local/share/digger/wordlist/${name}" \
           "/usr/share/digger/wordlist/${name}"; do
    if [[ -f "$p" ]]; then
      printf '%s' "$p"
      return 0
    fi
  done
  return 1
}

# Human readable byte count.
human_size() {
  local b="${1:-0}"
  if [[ "$b" =~ ^[0-9]+$ ]]; then
    if (( b >= 1048576 )); then
      awk -v n="$b" 'BEGIN{printf "%.1f MB", n/1048576}'
    elif (( b >= 1024 )); then
      awk -v n="$b" 'BEGIN{printf "%.1f KB", n/1024}'
    else
      printf '%s B' "$b"
    fi
  else
    printf '%s' "$b"
  fi
}

# ---------------------------------------------------------------------------
# Colours
# ---------------------------------------------------------------------------
init_colors() {
  if [[ -t 1 && -z "$NO_COLOR" && "${TERM:-dumb}" != "dumb" ]]; then
    C_RESET=$'\033[0m'
    C_BOLD=$'\033[1m'
    C_DIM=$'\033[2m'
    C_RED=$'\033[31m'
    C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m'
    C_CYAN=$'\033[36m'
  else
    C_RESET=''; C_BOLD=''; C_DIM=''
    C_RED=''; C_GREEN=''; C_YELLOW=''; C_CYAN=''
  fi
}

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------
have() { command -v "$1" >/dev/null 2>&1; }

# Compare a possibly fractional value against zero. Bash arithmetic cannot
# handle decimals, so this avoids (( )) for anything user supplied.
gt_zero() {
  local v="${1:-}"
  [[ -z "$v" ]] && return 1
  # strip a leading sign and surrounding whitespace
  v="${v// /}"
  [[ "$v" == -* ]] && v="${v#-}"
  # zero in any shape: 0, 0.0, 00.000, .0
  if [[ "$v" =~ ^0*(\.[0]*)?$ ]] && [[ -n "$v" ]]; then
    return 1
  fi
  [[ "$v" =~ ^[0-9]*\.?[0-9]+$ ]] || return 0
  return 0
}

# Detect a python that actually runs. Some systems ship a python3 shim that
# exists on PATH but fails when called (Windows Store alias, broken symlink),
# so existence alone is not good enough.
detect_python() {
  local c
  for c in python3 python; do
    if command -v "$c" >/dev/null 2>&1 && "$c" -c 'pass' >/dev/null 2>&1; then
      printf '%s' "$c"
      return 0
    fi
  done
  return 1
}

info() { printf '%s[+]%s %s\n' "$C_CYAN" "$C_RESET" "$*"; }
ok()   { printf '%s[*]%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '%s[!]%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
err()  { printf '%s[-]%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
die()  { err "$*"; exit 1; }

hr() {
  local n="${1:-60}"
  printf '%s%s%s\n' "$C_DIM" "$(printf '%*s' "$n" '' | tr ' ' '-')" "$C_RESET"
}

heading() { printf '\n%s%s%s\n' "$C_BOLD$C_CYAN" "$*" "$C_RESET"; }
label()   { printf '%s%s%s\n' "$C_BOLD" "$*" "$C_RESET"; }

pause() {
  [[ -t 0 ]] || return 0
  printf '\n%sPress ENTER to continue...%s' "$C_DIM" "$C_RESET"
  read -r _ || true
}

# ---------------------------------------------------------------------------
# Banner
# ---------------------------------------------------------------------------
term_width() {
  local w=""
  if have tput; then
    w=$(tput cols 2>/dev/null || true)
  fi
  if [[ -z "$w" && -n "${COLUMNS:-}" ]]; then
    w="$COLUMNS"
  fi
  [[ "$w" =~ ^[0-9]+$ ]] || w=80
  printf '%s' "$w"
}

show_banner() {
  (( SHOW_BANNER )) || return 0
  local width
  width=$(term_width)

  if (( width < 60 )); then
    printf '+--------------------------------------------+\n'
    printf '|  %s v%s%s\n' "$TOOL_NAME" "$VERSION" "$C_RESET"
    printf '|  passive first - loud when needed          |\n'
    printf '+--------------------------------------------+\n'
    return 0
  fi

  cat <<'EOF'
 ____ ___ ____  ____ _____ ____
|  _ \_ _/ ___|/ ___| ____|  _ \
| | | | | |  _| |  _|  _| | |_) |
| |_| | | |_| | |_| | |___|  _ <
|____/___\____|\____|_____|_| \_\
           DIGGER v1.0
passive first - loud when needed
EOF
}

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
  cat <<EOF
${C_BOLD}${TOOL_NAME} v${VERSION}${C_RESET} - passive first, loud when needed

${C_BOLD}USAGE${C_RESET}
  ./digger.sh                 launch the interactive menu
  ./digger.sh <command> [args] run a single module non-interactively

${C_BOLD}COMMANDS${C_RESET}
  myip                       your public IP, geo, ISP and ASN
  info <ip|host>             deep dive on an IP address or a website
  dns <domain|ip>            DNS records for a domain (A AAAA MX NS TXT CNAME SOA CAA)
  scan <host|ip>             TCP port scan (nmap -sT, or a /dev/tcp fallback)
  hosts <domain|ip>          reverse hosts on an address, optional vhost probing
  domain <domain>            registration data for a domain
  links <url>                crawl a site and list every link it finds
  subdomains <domain>        passive subdomains, wordlist and pattern guessing
  archive <domain|url>       archived snapshots, coverage and recent captures
  paths <url>                probe common paths and sensitive files
  tls <host[:port]>          certificates, protocol versions and ciphers
  cdn <domain|url>           CDN and WAF detection
  intel <ip|domain>          threat intel, DNSBL and blocklist lookups
  secrets <url>              crawl a site and flag API keys, tokens and leaks
  dorks <domain>             search engine dorks by category, offline
  social <handle|domain>     username checks across public platforms
  net <host|ip>              traceroute with ASN and network labels

${C_BOLD}OPTIONS${C_RESET}
  -h, --help                 this help
  --version                  print version
  --no-color                 disable ANSI colours
  --no-banner                suppress the banner
  --timeout <sec>            per-request HTTP timeout (default 15)
  -y, --yes                  assume yes for confirmation prompts

${C_BOLD}ENVIRONMENT${C_RESET}
  NO_COLOR=1                 disable colours (same as --no-color)
  ASSUME_YES=1               skip interactive confirmation prompts
  HTTP_TIMEOUT=15            per-request timeout in seconds

${C_BOLD}DEPENDENCIES${C_RESET}
  required    curl bash 4.3+
  json        jq, or python3 as a fallback for every json source
  optional    dig, nmap, openssl, whois, traceroute, mtr, ping
EOF
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
parse_args() {
  while (( $# > 0 )); do
    case "$1" in
      -h|--help)    usage; exit 0 ;;
      --version)    printf '%s %s\n' "$TOOL_NAME" "$VERSION"; exit 0 ;;
      --no-color)   NO_COLOR=1; init_colors ;;
      --no-banner)  SHOW_BANNER=0 ;;
      --timeout)    HTTP_TIMEOUT="${2:-15}"; shift ;;
      --yes|-y)     ASSUME_YES=1 ;;
      *)            break ;;
    esac
    shift
  done
  set -- "$@"
  ARGS=("$@")
}

# ---------------------------------------------------------------------------
# Prompting
# ---------------------------------------------------------------------------
prompt() {
  local label_text="$1" default="${2:-}" reply
  if [[ -n "$default" ]]; then
    read -r -p "${label_text} [${default}]: " reply || true
    printf '%s' "${reply:-$default}"
  else
    read -r -p "${label_text}: " reply || true
    printf '%s' "$reply"
  fi
}

confirm() {
  local text="$1" reply
  if [[ -n "$ASSUME_YES" ]]; then
    return 0
  fi
  if [[ ! -t 0 ]]; then
    return 1
  fi
  read -r -p "${text} [y/N] " reply || true
  [[ "$reply" =~ ^[Yy]([Ee][Ss])?$ ]]
}

# ---------------------------------------------------------------------------
# Validation helpers
# ---------------------------------------------------------------------------
is_ipv4() {
  local ip="$1" o
  [[ "$ip" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]] || return 1
  for o in "${BASH_REMATCH[@]:1:4}"; do
    (( o >= 0 && o <= 255 )) || return 1
  done
  return 0
}

is_ipv6() {
  local ip="$1"
  [[ "$ip" == *:* ]] || return 1
  [[ "$ip" =~ ^[0-9A-Fa-f:.]+$ ]] || return 1
  return 0
}

is_ip() { is_ipv4 "$1" || is_ipv6 "$1"; }

is_hostname() {
  local h="$1"
  [[ -n "$h" ]] || return 1
  (( ${#h} <= 253 )) || return 1
  [[ "$h" =~ ^([A-Za-z0-9_]([A-Za-z0-9_-]{0,61}[A-Za-z0-9_])?\.)*[A-Za-z0-9_]([A-Za-z0-9_-]{0,61}[A-Za-z0-9_])?$ ]] || return 1
  return 0
}

is_valid_target() {
  is_ip "$1" || is_hostname "$1"
}

# ---------------------------------------------------------------------------
# HTTP helpers
# ---------------------------------------------------------------------------
http_get() {
  local url="$1" timeout="${2:-$HTTP_TIMEOUT}" retries="${3:-$HTTP_RETRIES}"
  local attempt=0 out rc
  while (( attempt <= retries )); do
    attempt=$(( attempt + 1 ))
    set +e
    out=$(curl -sS -L --compressed \
      --max-time "$timeout" --connect-timeout "$timeout" \
      -H "User-Agent: $USER_AGENT" \
      -H 'Accept: */*' \
      -- "$url" 2>/dev/null </dev/null)
    rc=$?
    set -e
    if (( rc == 0 )) && [[ -n "$out" ]]; then
      printf '%s' "$out"
      return 0
    fi
    (( attempt <= retries )) && sleep 1
  done
  return 1
}

http_head() {
  local url="$1" timeout="${2:-$HTTP_TIMEOUT}" retries="${3:-$HTTP_RETRIES}"
  local attempt=0 out rc
  while (( attempt <= retries )); do
    attempt=$(( attempt + 1 ))
    set +e
    out=$(curl -sS -L -I --max-time "$timeout" --connect-timeout "$timeout" \
      -H "User-Agent: $USER_AGENT" \
      -- "$url" 2>/dev/null </dev/null)
    rc=$?
    set -e
    if (( rc == 0 )) && [[ -n "$out" ]]; then
      printf '%s' "$out"
      return 0
    fi
    (( attempt <= retries )) && sleep 1
  done
  return 1
}

http_code() {
  local url="$1" timeout="${2:-$HTTP_TIMEOUT}"
  set +e
  curl -sS -o /dev/null -L --max-time "$timeout" --connect-timeout "$timeout" \
    -H "User-Agent: $USER_AGENT" -w '%{http_code}' -- "$url" 2>/dev/null
  set -e
}

# ---------------------------------------------------------------------------
# JSON access: jq when available, python3 fallback, grep as last resort
# ---------------------------------------------------------------------------
read -r -d '' PY_JSON_GET <<'PYEOF' || true
import json, re, sys
try:
    sys.stdout.reconfigure(newline='\n')
except Exception:
    pass
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(1)

def resolve(cur, tokens):
    if not tokens:
        return cur
    tok = tokens[0]
    if tok == '[]':
        if not isinstance(cur, list):
            return None
        out = []
        for item in cur:
            r = resolve(item, tokens[1:])
            if r is None:
                continue
            if isinstance(r, list):
                out.extend(r)
            else:
                out.append(r)
        return out
    if tok.startswith('['):
        try:
            idx = int(tok[1:-1])
        except ValueError:
            return None
        if not isinstance(cur, list) or idx >= len(cur) or idx < -len(cur):
            return None
        return resolve(cur[idx], tokens[1:])
    if not isinstance(cur, dict):
        return None
    key = tok[1:]
    if key not in cur:
        return None
    return resolve(cur[key], tokens[1:])

tokens = re.findall(r'\.[A-Za-z0-9_-]+|\[\d*\]', sys.argv[1])
res = resolve(data, tokens)
if res is None:
    sys.exit(1)
if isinstance(res, list):
    for item in res:
        if isinstance(item, bool):
            print('true' if item else 'false')
        elif isinstance(item, (dict, list)):
            print(json.dumps(item))
        elif item is None:
            print('null')
        else:
            print(item)
elif isinstance(res, bool):
    print('true' if res else 'false')
elif isinstance(res, (dict, list)):
    print(json.dumps(res))
elif res is None:
    print('null')
else:
    print(res)
PYEOF

json_get() {
  local json="$1" filter="$2"
  [[ -n "$json" ]] || return 1
  if have jq; then
    printf '%s' "$json" | jq -r "$filter" 2>/dev/null
  elif [[ -n "$PY" ]]; then
    printf '%s' "$json" | "$PY" -c "$PY_JSON_GET" "$filter" 2>/dev/null
  else
    return 1
  fi
}

# Extract the first string value of a vcardArray entry.
# RDAP keeps names in vcardArray[1][n][3], e.g. the registrar name.
vcard_value() {
  local json="$1" path="$2" v=''
  v=$(json_get "$json" "$path") || return 1
  printf '%s' "$v"
}

# ---------------------------------------------------------------------------
# Misc helpers
# ---------------------------------------------------------------------------
url_encode() {
  local s="$1"
  if [[ -n "$PY" ]]; then
    "$PY" -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1],safe=""))' "$s" 2>/dev/null && return 0
  fi
  printf '%s' "$s" | sed -e 's/%/%25/g' -e 's/ /%20/g' -e 's|/|%2F|g' -e 's/?/%3F/g' -e 's/&/%26/g' -e 's/=/%3D/g' -e 's/+/%2B/g'
}

resolve_ip() {
  local host="$1" ip=''
  if is_ip "$host"; then
    printf '%s' "$host"
    return 0
  fi
  if have dig; then
    ip=$(dig +short +time=3 +tries=1 A "$host" 2>/dev/null | tail -n 1)
  fi
  if [[ -z "$ip" ]] && have getent; then
    ip=$(getent hosts "$host" 2>/dev/null | awk '{print $1; exit}')
  fi
  [[ -n "$ip" ]] || return 1
  printf '%s' "$ip"
}

is_private_ip() {
  local ip="$1"
  is_ipv4 "$ip" || return 1
  local o1 o2
  o1=$(printf '%s' "$ip" | cut -d. -f1)
  o2=$(printf '%s' "$ip" | cut -d. -f2)
  case "$o1" in
    10) return 0 ;;
    127) return 0 ;;
    169) [[ "$o2" == "254" ]] && return 0 ;;
    172) (( o2 >= 16 && o2 <= 31 )) && return 0 ;;
    192) [[ "$o2" == "168" ]] && return 0 ;;
  esac
  return 1
}

require_cmd() {
  local cmd="$1" hint="$2"
  if ! have "$cmd"; then
    err "missing required command: $cmd"
    [[ -n "$hint" ]] && printf '    %s\n' "$hint" >&2
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Dependency check
# ---------------------------------------------------------------------------
check_deps() {
  local missing=0
  if ! have curl; then
    err "missing required command: curl"
    printf '    %s\n' "sudo apt-get install -y curl" >&2
    missing=1
  fi
  return $missing
}

# ===========================================================================
# MODULES
# ===========================================================================

# ---------------------------------------------------------------------------
# HTTP convenience wrappers
# ---------------------------------------------------------------------------
# -k is deliberate: we are fingerprinting arbitrary hosts whose certificates
# are frequently self-signed or mismatched. We never act on the content.
final_status() {
  local url="$1" timeout="${2:-$HTTP_TIMEOUT}"
  set +e
  curl -sS -o /dev/null -L -k --max-time "$timeout" --connect-timeout "$timeout" \
    -H "User-Agent: $USER_AGENT" -w '%{http_code}' -- "$url" 2>/dev/null
  set -e
}

# Headers of the final response in a redirect chain.
final_headers() {
  local url="$1" timeout="${2:-$HTTP_TIMEOUT}"
  set +e
  curl -sS -o /dev/null -D - -L -k --max-time "$timeout" --connect-timeout "$timeout" \
    -H "User-Agent: $USER_AGENT" -- "$url" 2>/dev/null \
    | awk 'BEGIN{RS="\n\n"} {buf=$0} END{printf "%s", buf}'
  set -e
}

header_value() {
  local headers="$1" name="$2" v=''
  v=$(printf '%s' "$headers" | grep -i "^${name}:" | tail -n1 | cut -d: -f2- \
    | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' || true)
  printf '%s' "$v"
}

header_present() {
  local headers="$1" name="$2"
  printf '%s' "$headers" | grep -qi "^${name}:" || return 1
  return 0
}

page_body() {
  local url="$1" limit="${2:-500000}" body=''
  body=$(curl -sS -L -k --max-time 20 -H "User-Agent: $USER_AGENT" -- "$url" 2>/dev/null \
    | head -c "$limit" || true)
  printf '%s' "$body"
}

page_title() {
  local url="$1" body='' title=''
  body=$(page_body "$url")
  title=$(printf '%s' "$body" | tr '\n' ' ' \
    | grep -oiE '<title[^>]*>[^<]{0,300}' | head -n1 \
    | sed -E 's/<title[^>]*>//I' || true)
  printf '%s' "$title"
}

rdap_get() {
  http_get "https://rdap.org/${1}" "$HTTP_TIMEOUT" 1
}

# RDAP keeps contact details inside vcardArray entries. Fetch the first
# value of a given field (fn, org, email, tel) for an entity holding a role
# such as registrar, registrant or abuse.
read -r -d '' PY_RDAP_ROLE <<'PYEOF' || true
import json, sys
try:
    sys.stdout.reconfigure(newline='\n')
except Exception:
    pass
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(1)
role, field = sys.argv[1], sys.argv[2]
found = []
def walk(entities):
    for e in entities or []:
        if role in (e.get('roles') or []):
            va = e.get('vcardArray')
            if va and len(va) > 1:
                for item in va[1]:
                    if isinstance(item, list) and len(item) > 3 and item[0] == field:
                        found.append(item[3])
                        break
        walk(e.get('entities'))
walk(d.get('entities'))
if found:
    print(found[0])
PYEOF

rdap_role_field() {
  local json="$1" role="$2" field="$3" out=''
  [[ -n "$json" ]] || return 1
  if [[ -n "$PY" ]]; then
    out=$(printf '%s' "$json" | "$PY" -c "$PY_RDAP_ROLE" "$role" "$field" 2>/dev/null || true)
  elif have jq; then
    out=$(printf '%s' "$json" | jq -r --arg r "$role" --arg f "$field" \
      '[.. | objects | select(((.roles? // []) | index($r)) != null) | .vcardArray[1][]? | select(.[0] == $f) | .[3]] | first // empty' \
      2>/dev/null || true)
  fi
  [[ -n "$out" ]] || return 1
  printf '%s' "$out"
}

# Resolve a hostname to its first A record. Uses dig when present, falls back
# to the DNS-over-HTTPS resolver so the tool still works on a bare box.
resolve_host() {
  local host="$1" ip=''
  if have dig; then
    ip=$(dig +short +time=3 +tries=1 A "$host" 2>/dev/null | tail -n1 || true)
  fi
  if [[ -z "$ip" ]] && have getent; then
    ip=$(getent hosts "$host" 2>/dev/null | awk '{print $1; exit}' || true)
  fi
  if [[ -z "$ip" ]]; then
    local json
    json=$(http_get "https://dns.google/resolve?name=${host}&type=A" "$HTTP_TIMEOUT" 1) || json=''
    if [[ -n "$json" ]]; then
      ip=$(json_get "$json" '.Answer[].data' 2>/dev/null | head -n1 || true)
    fi
  fi
  [[ -n "$ip" ]] || return 1
  printf '%s' "$ip"
}

# Query a DNS record type. dig when available, DNS over HTTPS otherwise.
# Returns one record per line.
dns_query() {
  local name="$1" type="$2" out=''
  if have dig; then
    out=$(dig +short +time=4 +tries=1 "$type" "$name" 2>/dev/null || true)
  fi
  if [[ -z "$out" ]]; then
    local json
    json=$(http_get "https://dns.google/resolve?name=${name}&type=${type}" "$HTTP_TIMEOUT" 1) || json=''
    if [[ -n "$json" ]]; then
      out=$(json_get "$json" '.Answer[].data' 2>/dev/null || true)
      out=$(printf '%s' "$out" | tr -d '"')
    fi
  fi
  [[ -z "$out" ]] && return 1
  printf '%s' "$out"
}

# Follow a CNAME chain and print every hop, one per line.
dns_cname_chain() {
  local host="$1"
  local -a hops=()
  local current="$host" guard=0
  while (( guard < 10 )); do
    guard=$((guard + 1))
    local cname
    cname=$(dns_query "$current" CNAME 2>/dev/null | head -n1 || true)
    [[ -z "$cname" ]] && break
    cname="${cname%.}"
    [[ "$cname" == "$current" ]] && break
    hops+=("$cname")
    current="$cname"
  done
  (( ${#hops[@]} == 0 )) && return 1
  printf '%s' "${hops[*]}"
}

# ---------------------------------------------------------------------------
# Fingerprinting helpers
# ---------------------------------------------------------------------------
detect_tech() {
  local headers="$1" body="$2"
  local -a out=()
  local sig val

  for sig in \
    'server:nginx' 'server:apache' 'server:cloudflare' 'server:cloudfront' \
    'server:amazonS3' 'server:Microsoft-IIS' 'server:gunicorn' 'server:openresty' \
    'server:caddy' 'server:lighttpd' 'server:werkzeug' 'server:envoy' 'server:LiteSpeed' \
    'x-powered-by:php' 'x-powered-by:asp.net' 'x-powered-by:express' \
    'x-aspnet-version' 'x-drupal-cache' 'x-generator:drupal' 'x-generator:wordpress' \
    'x-shopify-stage' 'x-magento-tags' 'x-varnish' 'x-varnish-hits' \
    'cf-ray' 'x-amz-cf-id' 'x-amz-cf-pop' 'x-akamai-transformed' 'x-served-by' \
    'x-azure-ref' 'x-ms-request-id' 'x-fastly-request-id' 'x-github-request-id' \
    'x-nextjs-cache' 'x-nf-request-id' ; do
    if header_present "$headers" "${sig%%:*}"; then
      val=$(header_value "$headers" "${sig%%:*}")
      [[ "$val" == "${sig#*:}"* ]] || continue
      out+=("$(printf '%-18s %s' "${sig%%:*}" "$val")")
    fi
  done

  local meta gen
  meta=$(printf '%s' "$body" | grep -oiE '<meta[^>]+name=["'"'"']generator["'"'"'][^>]*>' | head -n1 || true)
  if [[ -n "$meta" ]]; then
    out+=("$(printf '%-18s %s' "generator" "$(printf '%s' "$meta" | sed -E 's/.*content=["'"'"']([^"'"'"']*).*/\1/I')")")
  fi

  for gen in 'wp-content' 'wp-includes' 'cdn.jsdelivr.net' 'cdnjs.cloudflare.com' \
             'unpkg.com' 'google-analytics.com' 'googletagmanager.com' 'gtm.js' \
             'jquery.min.js' 'bootstrap.min.css' 'shopify' 'squarespace' 'wix' \
             'typo3' 'drupal.js' 'umbraco' 'sitefinity' 'hubspot' 'marketo' \
             'intercom' 'zendesk' 'livechat' 'hotjar' ; do
    if printf '%s' "$body" | grep -qi -- "$gen"; then
      out+=("$(printf '%-18s %s' "markup" "$gen")")
    fi
  done

  (( ${#out[@]} == 0 )) && return 0
  printf '%s\n' "${out[@]}"
  return 0
}

tls_summary() {
  local host="$1" port="${2:-443}" info='' cert='' chain=0 i=0
  local timeout=15

  info=$(timeout "$timeout" openssl s_client -connect "${host}:${port}" -servername "$host" \
    -showcerts </dev/null 2>/dev/null || true)

  [[ -n "$info" ]] || return 1

  # count the certificates in the chain
  chain=$(printf '%s' "$info" | grep -c -- "-----BEGIN CERTIFICATE" || true)

  # leaf certificate
  cert=$(printf '%s' "$info" | awk '/-----BEGIN CERTIFICATE-----/{f=1} f{print} /-----END CERTIFICATE-----/{exit}' || true)
  [[ -n "$cert" ]] || return 1

  printf '  Chain length   : %s\n' "$chain"
  printf '  Subject        : %s\n' "$(printf '%s' "$cert" | openssl x509 -noout -subject 2>/dev/null | sed 's/^subject=//' | sed 's/^ *//' || true)"
  printf '  Issuer         : %s\n' "$(printf '%s' "$cert" | openssl x509 -noout -issuer 2>/dev/null | sed 's/^issuer=//' | sed 's/^ *//' || true)"
  printf '  Valid from     : %s\n' "$(printf '%s' "$cert" | openssl x509 -noout -startdate 2>/dev/null | sed 's/^notBefore=//' || true)"
  printf '  Valid until    : %s\n' "$(printf '%s' "$cert" | openssl x509 -noout -enddate 2>/dev/null | sed 's/^notAfter=//' || true)"
  printf '  Serial         : %s\n' "$(printf '%s' "$cert" | openssl x509 -noout -serial 2>/dev/null | sed 's/^serial=//' || true)"
  printf '  Key type/size  : %s\n' "$(printf '%s' "$cert" | openssl x509 -noout -text 2>/dev/null | grep -iE 'Public-Key' | head -n1 | sed 's/^ *//' || true)"
  printf '  Signature alg  : %s\n' "$(printf '%s' "$cert" | openssl x509 -noout -text 2>/dev/null | grep -iE 'Signature Algorithm' | head -n1 | sed 's/^ *//' || true)"
  local san
  san=$(printf '%s' "$cert" | openssl x509 -noout -ext subjectAltName 2>/dev/null | tail -n1 | sed 's/^ *//' || true)
  [[ -n "$san" ]] && printf '  SANs           : %s\n' "$san"
  return 0
}

# ---------------------------------------------------------------------------
# URL helpers
# ---------------------------------------------------------------------------
url_join() {
  local base="$1" href="$2" py_out=''
  href="${href%%#*}"
  [[ -z "$href" ]] && return 1
  # Values travel through the environment with a one character prefix: MSYS
  # (Git Bash on Windows) rewrites arguments that look like absolute POSIX
  # paths, so "/app.js" would otherwise become "C:/Program Files/Git/app.js"
  # before python sees it.
  if [[ -n "$PY" ]]; then
    py_out=$(JOIN_BASE="x${base}" JOIN_HREF="x${href}" "$PY" -c \
      'import os,urllib.parse as u;b=os.environ["JOIN_BASE"][1:];h=os.environ["JOIN_HREF"][1:];print(u.urljoin(b,h))' \
      2>/dev/null || true)
    if [[ -n "$py_out" ]]; then
      printf '%s' "$py_out"
      return 0
    fi
  fi

  # bash fallback
  case "$href" in
    http://*|https://*) printf '%s' "$href"; return 0 ;;
    //*) printf '%s:%s' "${base%%://*}" "$href"; return 0 ;;
  esac
  local scheme="${base%%://*}"
  local rest="${base#*://}"
  local host="${rest%%/*}"
  local path="${rest#*/}"
  [[ "$path" == "$rest" ]] && path="/"
  case "$href" in
    /*) path="$href" ;;
    *)  path="${path%/*}/$href" ;;
  esac
  local -a parts=() out_parts=()
  local IFS='/'
  read -r -a parts <<< "$path"
  unset IFS
  local seg
  for seg in "${parts[@]}"; do
    case "$seg" in
      ''|'.') continue ;;
      '..') if (( ${#out_parts[@]} > 0 )); then
              out_parts=("${out_parts[@]:0:${#out_parts[@]}-1}")
            fi ;;
      *) out_parts+=("$seg") ;;
    esac
  done
  local joined
  joined=$(IFS='/'; printf '%s' "${out_parts[*]}")
  printf '%s://%s/%s' "$scheme" "$host" "$joined"
}

url_host() {
  printf '%s' "$1" | sed -E 's#^[a-z]+://([^/]+).*#\1#'
}

url_path() {
  printf '%s' "$1" | sed -E 's#^[a-z]+://[^/]+##'
}

# Percent encode a query value for a search engine URL.
urlencode_q() {
  local s="$1" enc_out='' quote="'"
  # Prefix the value for the same reason as url_join: MSYS rewrites anything
  # that looks like a POSIX path before the python process starts.
  if [[ -n "$PY" ]]; then
    enc_out=$(URLENC_IN="x${s}" "$PY" -c \
      'import os,urllib.parse;print(urllib.parse.quote_plus(os.environ["URLENC_IN"][1:]))' \
      2>/dev/null || true)
    if [[ -n "$enc_out" ]]; then
      printf '%s' "$enc_out"
      return 0
    fi
  fi
  s="${s//%/%25}"
  s="${s// /+}"
  s="${s//\"/%22}"
  s="${s//:/%3A}"
  s="${s//\//%2F}"
  s="${s//\?/%3F}"
  s="${s//&/%26}"
  s="${s//=/%3D}"
  s="${s//#/%23}"
  s="${s//</%3C}"
  s="${s//>/%3E}"
  s="${s//$quote/%27}"
  printf '%s' "$s"
}

# Pull every candidate link out of an HTML document.
extract_links() {
  local body="$1"
  {
    printf '%s' "$body" \
      | grep -oiE '(href|src|action|poster|data-src|data-url|data-href)\s*=\s*"[^"]*"' \
      | sed -E 's/^[A-Za-z-]+\s*=\s*"//; s/"$//' || true
    printf '%s' "$body" \
      | grep -oiE "(href|src|action|poster|data-src|data-url|data-href)\s*=\s*'[^']*'" \
      | sed -E "s/^[A-Za-z-]+\s*=\s*'//; s/'\$//" || true
    printf '%s' "$body" \
      | grep -oiE '(href|src|action|poster)\s*=\s*[A-Za-z0-9_./?=&%:+~-]+' \
      | sed -E 's/^[A-Za-z-]+\s*=\s*//' || true
    printf '%s' "$body" \
      | grep -oiE '(srcset|data-srcset)\s*=\s*"[^"]*"' \
      | sed -E 's/^[A-Za-z-]+\s*=\s*"//; s/"$//' \
      | sed -E 's/,[[:space:]]+/\n/g' | awk '{print $1}' || true
    printf '%s' "$body" \
      | grep -oiE 'url\([^)]*\)' \
      | sed -E 's/^url\(//; s/\)$//; s/^["'"'"']//; s/["'"'"']$//' || true
  } | sed 's/[[:space:]]*$//' | awk 'length($0) > 0'
}

# --- Module 7: Extract Links ----------------------------------------------
mod_links() {
  local target="" depth=5 maxpages=100 delay="0.3" external=0 ignore_robots=0

  while (( $# > 0 )); do
    case "$1" in
      --depth)            depth="${2:-5}"; shift 2 || shift ;;
      --max-pages)        maxpages="${2:-100}"; shift 2 || shift ;;
      --delay)            delay="${2:-0.3}"; shift 2 || shift ;;
      --include-external) external=1; shift ;;
      --ignore-robots)    ignore_robots=1; shift ;;
      -h|--help)
        printf 'usage: digger.sh links <url> [--depth N] [--max-pages N] [--delay S] [--include-external] [--ignore-robots]\n'
        return 0 ;;
      *)
        if [[ -z "$target" ]]; then target="$1"; fi
        shift ;;
    esac
  done

  heading "EXTRACT LINKS"
  hr 60

  if [[ -z "$target" ]]; then
    target=$(prompt "Start URL")
  fi
  target="${target// /}"
  if [[ -z "$target" ]]; then
    err "no URL given"
    return 1
  fi
  [[ "$target" != http://* && "$target" != https://* ]] && target="https://${target}"
  target="${target%/}"

  local hostpart="${target#*://}"
  hostpart="${hostpart%%/*}"
  hostpart="${hostpart%%:*}"
  if ! is_hostname "$hostpart" && ! is_ip "$hostpart"; then
    err "invalid URL: ${target}"
    return 1
  fi

  info "Target: ${C_BOLD}${target}${C_RESET}"
  printf '  Limits      : depth %s, max pages %s, delay %ss\n' "$depth" "$maxpages" "$delay"

  # --- robots.txt ---------------------------------------------------------
  local -a disallow=()
  if (( ! ignore_robots )) && have curl; then
    local robots
    robots=$(http_get "${target}/robots.txt" 10 0) || robots=''
    if [[ -n "$robots" ]]; then
      local line path agent in_star=0
      while IFS= read -r line; do
        line="${line%%#*}"
        line=$(printf '%s' "$line" | tr -d '\r' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
        local lower="${line,,}"
        case "$lower" in
          user-agent:*)
            in_star=0
            agent=$(printf '%s' "${line#*:}" | sed 's/^[[:space:]]*//')
            [[ "$agent" == "*" ]] && in_star=1 ;;
          disallow:*)
            if (( in_star == 1 )); then
              path=$(printf '%s' "${line#*:}" | sed 's/^[[:space:]]*//')
              [[ -n "$path" ]] && disallow+=("$path")
            fi ;;
        esac
      done <<< "$robots"
    fi
  fi

  is_disallowed() {
    local path="$1" d
    for d in ${disallow[@]+"${disallow[@]}"}; do
      [[ -z "$d" ]] && continue
      [[ "$path" == "$d"* ]] && return 0
    done
    return 1
  }

  local base_host
  base_host=$(url_host "$target")

  local -A seen=()
  local -a queue=() pages=() internal=() external_links=()
  queue+=("0|${target}")

  local pages_n=0 links_n=0
  while (( ${#queue[@]} > 0 )); do
    local entry="${queue[0]}"
    queue=("${queue[@]:1}")
    local d="${entry%%|*}" u="${entry#*|}"
    (( d > depth )) && continue
    [[ -n "${seen[$u]:-}" ]] && continue
    (( pages_n >= maxpages )) && break

    local path
    path=$(url_path "$u")
    if (( ${#disallow[@]} > 0 )) && is_disallowed "$path"; then
      continue
    fi

    seen["$u"]=1
    local body
    body=$(page_body "$u" 400000)
    [[ -z "$body" ]] && continue

    pages_n=$((pages_n + 1))
    pages+=("$u")

    local link abs ahost
    while IFS= read -r link; do
      [[ -z "$link" ]] && continue
      case "${link,,}" in
        javascript:*|mailto:*|tel:*|data:*|about:*|ftp:*|blob:*|file:*) continue ;;
      esac
      abs=$(url_join "$u" "$link" || true)
      [[ -z "$abs" ]] && continue
      case "$abs" in
        http://*|https://*) ;;
        *) continue ;;
      esac
      links_n=$((links_n + 1))
      ahost=$(url_host "$abs")
      if [[ "$ahost" == "$base_host" ]]; then
        internal+=("$abs")
        if (( d < depth )) && [[ -z "${seen[$abs]:-}" ]]; then
          queue+=("$((d + 1))|${abs}")
        fi
      else
        external_links+=("$abs")
        if (( external )) && (( d < depth )) && [[ -z "${seen[$abs]:-}" ]]; then
          queue+=("$((d + 1))|${abs}")
        fi
      fi
    done < <(extract_links "$body")

    if gt_zero "$delay"; then sleep "$delay"; fi
  done

  printf '\n%sResult%s\n' "$C_BOLD" "$C_RESET"
  printf '  Pages crawled : %s\n' "$pages_n"
  printf '  Links seen    : %s\n' "$links_n"

  if (( ${#pages[@]} > 0 )); then
    printf '\n%sPages%s\n' "$C_BOLD" "$C_RESET"
    printf '%s\n' "${pages[@]}" | sed 's/^/  /'
  fi

  local uniq_int uniq_ext
  uniq_int=$(printf '%s\n' ${internal[@]+"${internal[@]}"} | sed '/^$/d' | sort -u)
  uniq_ext=$(printf '%s\n' ${external_links[@]+"${external_links[@]}"} | sed '/^$/d' | sort -u)

  if [[ -n "$uniq_int" ]]; then
    printf '\n%sInternal links%s (%s)\n' "$C_BOLD" "$C_RESET" "$(printf '%s\n' "$uniq_int" | grep -c . || true)"
    printf '%s\n' "$uniq_int" | sed 's/^/  /'
  fi
  if [[ -n "$uniq_ext" ]]; then
    printf '\n%sExternal links%s (%s)\n' "$C_BOLD" "$C_RESET" "$(printf '%s\n' "$uniq_ext" | grep -c . || true)"
    printf '%s\n' "$uniq_ext" | sed 's/^/  /'
  fi
  return 0
}

# --- Module 17: Network Path -----------------------------------------------
# Traceroute with ASN enrichment. Everything keyless: the local traceroute
# does the probing, Team Cymru's DNS zone (over DoH) labels the networks.
net_is_private() {
  local ip="$1"
  [[ "$ip" =~ ^10[.] ]] && return 0
  [[ "$ip" =~ ^192[.]168[.] ]] && return 0
  [[ "$ip" =~ ^172[.](1[6-9]|2[0-9]|3[01])[.] ]] && return 0
  [[ "$ip" =~ ^127[.] ]] && return 0
  [[ "$ip" == '::1' ]] && return 0
  return 1
}

net_shorten() {
  local s="$1" w="${2:-42}"
  if (( ${#s} > w )); then
    printf '%s...' "${s:0:w-3}"
  else
    printf '%s' "$s"
  fi
}

# One hop line per reply: number<TAB>ip<TAB>name<TAB>rtt
net_parse_traceroute() {
  local line n rest ip name rtt
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*([0-9]+)[[:space:]]+(.*)$ ]] || continue
    n="${BASH_REMATCH[1]}"
    rest="${BASH_REMATCH[2]}"
    if [[ "$rest" == '*'* ]]; then
      printf '%s\t*\t-\t-\n' "$n"
      continue
    fi
    if [[ "$rest" =~ ^([^[:space:]]+)[[:space:]]+\(([^\)]+)\) ]]; then
      name="${BASH_REMATCH[1]}"
      ip="${BASH_REMATCH[2]}"
      rest="${rest#*)}"
    else
      ip="${rest%%[[:space:]]*}"
      name=''
      rest="${rest#"$ip"}"
    fi
    rtt=''
    if [[ "$rest" =~ ([0-9]+([.][0-9]+)?)[[:space:]]+ms ]]; then
      rtt="${BASH_REMATCH[1]}"
    fi
    [[ -z "$rtt" ]] && rtt='-'
    printf '%s\t%s\t%s\t%s\n' "$n" "$ip" "$name" "$rtt"
  done <<< "$1"
}

# mtr -r -n rows: "  1.|-- 192.168.1.1   0.0%     1   1.2 ..."
net_parse_mtr() {
  local line n ip loss avg
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*([0-9]+)[.]\|--[[:space:]]+([^[:space:]]+) ]] || continue
    n="${BASH_REMATCH[1]}"
    ip="${BASH_REMATCH[2]}"
    loss=$(printf '%s' "$line" | awk '{print $3}' | tr -d '%')
    avg=$(printf '%s' "$line" | awk '{print $6}')
    [[ "$ip" == '???' ]] && ip='*'
    if [[ "$ip" == '*' || "${loss:-0}" == '100' ]]; then
      printf '%s\t*\t-\t-\n' "$n"
      continue
    fi
    [[ "$avg" =~ ^[0-9.]+$ ]] || avg='-'
    printf '%s\t%s\t-\t%s\n' "$n" "$ip" "$avg"
  done <<< "$1"
}

# Ping walking TTLs: works unprivileged on Linux when ping has cap_net_raw.
net_ping_trace() {
  local host="$1" maxhops="$2" wait="$3"
  local ttl out ip rtt
  for (( ttl = 1; ttl <= maxhops; ttl++ )); do
    out=$(ping -c 1 -W "$wait" -t "$ttl" "$host" 2>&1 || true)
    rtt='-'
    if [[ "$out" =~ time=([0-9.]+)[[:space:]]*ms ]]; then
      rtt="${BASH_REMATCH[1]}"
    fi
    if [[ "$out" =~ [Tt]ime[[:space:]]to[[:space:]]live[[:space:]]exceeded || "$out" =~ TTL[[:space:]]expired ]]; then
      if [[ "$out" =~ [Ff]rom[[:space:]]+([0-9A-Fa-f.:]+) ]]; then
        ip="${BASH_REMATCH[1]%:}"
        printf '%s\t%s\t-\t%s\n' "$ttl" "$ip" "$rtt"
        continue
      fi
    fi
    if [[ "$out" =~ [0-9]+[[:space:]]+bytes[[:space:]]+from[[:space:]]+([0-9A-Fa-f.:]+) ]]; then
      ip="${BASH_REMATCH[1]%:}"
      printf '%s\t%s\t-\t%s\n' "$ttl" "$ip" "$rtt"
      return 0
    fi
    printf '%s\t*\t-\t-\n' "$ttl"
  done
  return 0
}

net_ping_supports_ttl() {
  local out
  out=$(ping -c 1 -W 1 -t 1 127.0.0.1 2>&1 || true)
  [[ "$out" == *bytes*from* || "$out" == *'bytes from'* ]]
}

# Resolve one address to "AS<number> | prefix | organisation".
net_asn_lookup() {
  local ip="$1" name json txt asn prefix org t
  [[ -z "$ip" || "$ip" == '*' ]] && return 0
  net_is_private "$ip" && return 0
  is_ipv4 "$ip" || return 0

  name=$(printf '%s' "$ip" | awk -F. '{print $4"."$3"."$2"."$1".origin.asn.cymru.com"}')
  json=$(http_get "https://dns.google/resolve?name=${name}&type=TXT" 12 0) || json=''
  txt=$(json_get "$json" '.Answer[].data' 2>/dev/null | head -n1 || true)
  txt="${txt#\"}"; txt="${txt%\"}"
  [[ -z "$txt" ]] && return 0

  asn=$(printf '%s' "$txt" | cut -d'|' -f1 | tr -d ' ')
  prefix=$(printf '%s' "$txt" | cut -d'|' -f2 | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')
  org=''
  if [[ -n "$asn" ]]; then
    json=$(http_get "https://dns.google/resolve?name=AS${asn}.asn.cymru.com&type=TXT" 12 0) || json=''
    t=$(json_get "$json" '.Answer[].data' 2>/dev/null | head -n1 || true)
    t="${t#\"}"; t="${t%\"}"
    if [[ -n "$t" ]]; then
      org=$(printf '%s' "$t" | cut -d'|' -f5 | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')
    fi
  fi
  printf '%s\t%s\t%s\t%s\n' "$ip" "${asn:+AS${asn}}" "${prefix:--}" "${org:--}"
}

# Look up every hop concurrently; results arrive as lines for the caller.
net_asn_all() {
  local -a pids=()
  local ip
  for ip in "$@"; do
    net_asn_lookup "$ip" &
    pids+=($!)
    if (( ${#pids[@]} >= 5 )); then
      wait "${pids[0]}" 2>/dev/null || true
      pids=("${pids[@]:1}")
    fi
  done
  wait 2>/dev/null || true
}

mod_net() {
  local target='' maxhops=20 wait=2 no_asn=0
  local hops_out='' used_engine=''

  while (( $# > 0 )); do
    case "$1" in
      --max-hops) maxhops="${2:-20}"; shift 2 || shift ;;
      --timeout)  wait="${2:-2}"; shift 2 || shift ;;
      --no-asn)   no_asn=1; shift ;;
      -y|--yes)   ASSUME_YES=1; shift ;;
      -h|--help)
        printf 'usage: digger.sh net <host|ip> [--max-hops N] [--timeout SEC] [--no-asn]\n'
        return 0 ;;
      *)
        if [[ -z "$target" ]]; then target="$1"; fi
        shift ;;
    esac
  done

  heading "NETWORK PATH"
  hr 60

  if [[ -z "$target" ]]; then
    target=$(prompt "Host or IP")
  fi
  target="${target// /}"
  if [[ -z "$target" ]]; then
    err "no target given"
    return 1
  fi
  target="${target#*://}"
  target="${target%%/*}"
  target="${target%.}"
  target="${target,,}"
  if ! is_valid_target "$target"; then
    err "invalid target: ${target}"
    return 1
  fi

  [[ "$maxhops" =~ ^[0-9]+$ ]] && (( maxhops > 0 && maxhops <= 64 )) || maxhops=20
  [[ "$wait" =~ ^[0-9]+$ ]] && (( wait > 0 )) || wait=2

  local ip=''
  if is_ip "$target"; then
    ip="$target"
  else
    ip=$(resolve_host "$target" || true)
  fi
  if [[ -z "$ip" ]]; then
    err "could not resolve ${target}"
    return 1
  fi

  local ptr
  ptr=$(host_ptr "$ip" || true)
  info "Target: ${C_BOLD}${target}${C_RESET} (${ip})"
  [[ -n "$ptr" && "$ptr" != "$target" ]] && printf '  PTR         : %s\n' "$ptr"

  # --- engine selection ---------------------------------------------------
  local can_ping=0
  have ping && net_ping_supports_ttl && can_ping=1

  printf '\n%sTrace%s\n' "$C_BOLD" "$C_RESET"
  printf '  max hops    : %s\n' "$maxhops"
  printf '  wait        : %ss per probe\n' "$wait"
  if have traceroute; then
    printf '  engine      : traceroute (UDP probes, no root)\n'
  elif have mtr; then
    printf '  engine      : mtr (report mode)\n'
  elif (( can_ping )); then
    printf '  engine      : ping with a walking TTL %s(no traceroute installed)%s\n' \
      "$C_DIM" "$C_RESET"
  else
    printf '  engine      : %snone available%s\n' "$C_YELLOW" "$C_RESET"
  fi
  (( no_asn )) && printf '  enrichment  : disabled (--no-asn)\n'

  if ! have traceroute && ! have mtr && (( can_ping == 0 )); then
    warn "no traceroute, mtr or TTL capable ping found"
    printf '  %sinstall traceroute or mtr to map the path%s\n' "$C_DIM" "$C_RESET"
    return 0
  fi

  if ! confirm "This sends up to ${maxhops} trace probes towards ${ip}. Continue?"; then
    warn "aborted"
    return 0
  fi

  # --- run the trace ------------------------------------------------------
  local -a hop_lines=()
  local tmo=$(( maxhops * wait + 15 ))

  if have traceroute; then
    hops_out=$(timeout "$tmo" traceroute -m "$maxhops" -w "$wait" -q 1 "$ip" 2>&1 || true)
    if [[ -n "$hops_out" ]]; then
      mapfile -t hop_lines < <(net_parse_traceroute "$hops_out")
      (( ${#hop_lines[@]} > 0 )) && used_engine='traceroute'
    fi
  fi

  if (( ${#hop_lines[@]} == 0 )) && have mtr; then
    hops_out=$(timeout "$tmo" mtr -r -c 1 -n --udp -m "$maxhops" "$ip" 2>&1 || true)
    if [[ -n "$hops_out" ]]; then
      mapfile -t hop_lines < <(net_parse_mtr "$hops_out")
      (( ${#hop_lines[@]} > 0 )) && used_engine='mtr'
    fi
  fi

  if (( ${#hop_lines[@]} == 0 )) && (( can_ping )); then
    used_engine='ping'
    mapfile -t hop_lines < <(net_ping_trace "$ip" "$maxhops" "$wait")
  fi

  if (( ${#hop_lines[@]} == 0 )); then
    warn "the trace produced no hops"
    printf '%s\n' "$hops_out" | sed -n '1,5p'
    return 0
  fi

  # --- ASN enrichment -----------------------------------------------------
  local -A asn_info=()
  local -A seen_ip=()
  local -a uniq_ips=()
  local line n hip hname rtt
  for line in "${hop_lines[@]}"; do
    IFS=$'\t' read -r n hip hname rtt <<< "$line"
    [[ "$hip" == '*' ]] && continue
    [[ -n "${seen_ip[$hip]:-}" ]] && continue
    net_is_private "$hip" && continue
    seen_ip["$hip"]=1
    uniq_ips+=("$hip")
  done

  if (( no_asn == 0 )) && (( ${#uniq_ips[@]} > 0 )); then
    printf '\n  %slooking up %s networks...%s\n' "$C_DIM" "${#uniq_ips[@]}" "$C_RESET"
    local raw_asn a_ip a_asn a_prefix a_org
    raw_asn=$(net_asn_all "${uniq_ips[@]}")
    while IFS=$'\t' read -r a_ip a_asn a_prefix a_org; do
      [[ -z "$a_ip" ]] && continue
      asn_info["$a_ip"]="${a_asn}|${a_prefix}|${a_org}"
    done <<< "$raw_asn"
  fi

  # --- display ------------------------------------------------------------
  printf '\n%sHops%s\n' "$C_BOLD" "$C_RESET"
  printf '  %s%-3s %-44s %-9s %-20s %s%s\n' "$C_DIM" '#' 'ADDRESS' 'ASN' 'NETWORK' 'RTT' "$C_RESET"

  local replies=0 silent=0 reached=0 last_asn=''
  local addr info_line asn prefix org
  for line in "${hop_lines[@]}"; do
    IFS=$'\t' read -r n hip hname rtt <<< "$line"
    if [[ "$hip" == '*' ]]; then
      printf '  %s%-3s %-44s %-9s %-20s %s%s\n' "$C_DIM" "$n" '*' '-' '-' '-' "$C_RESET"
      silent=$((silent + 1))
      continue
    fi
    replies=$((replies + 1))
    addr="$hip"
    [[ -n "$hname" && "$hname" != "$hip" && "$hname" != '-' ]] && addr="${hname} (${hip})"
    asn='-'; prefix='-'; org=''
    info_line="${asn_info[$hip]:-}"
    if [[ -n "$info_line" ]]; then
      IFS='|' read -r asn prefix org <<< "$info_line"
    fi
    local rtt_col='-'
    [[ "$rtt" != '-' ]] && rtt_col="${rtt} ms"
    printf '  %-3s %-44s %-9s %-20s %s\n' "$n" "$(net_shorten "$addr" 44)" "$asn" \
      "$(net_shorten "$prefix" 20)" "$rtt_col"
    [[ "$asn" != '-' ]] && last_asn="${asn}|${org}"
    if [[ "$hip" == "$ip" ]]; then
      reached=1
    fi
  done

  # --- summary ------------------------------------------------------------
  printf '\n%sSummary%s\n' "$C_BOLD" "$C_RESET"
  printf '  Target   : %s (%s)\n' "$target" "$ip"
  printf '  Engine   : %s\n' "${used_engine:-unknown}"
  printf '  Hops     : %s (%s replied, %s silent)\n' \
    "${#hop_lines[@]}" "$replies" "$silent"
  if (( reached )); then
    printf '  Reached  : yes\n'
  else
    printf '  Reached  : %sno direct reply from %s%s\n' "$C_DIM" "$ip" "$C_RESET"
  fi
  if [[ -n "$last_asn" ]]; then
    asn="${last_asn%%|*}"
    org="${last_asn#*|}"
    printf '  Last ASN : %s %s\n' "$asn" "$org"
  fi
  return 0
}

# --- Module 16: Social Footprint -------------------------------------------
# Username checks against public profile pages: only platforms that answer
# with a real 404 (or an unambiguous "no such user" page) are included.
social_platforms() {
  local h="$1"
  cat <<EOF
GitHub|https://github.com/${h}|
Bitbucket|https://bitbucket.org/${h}|
Keybase|https://keybase.io/${h}|
Docker Hub|https://hub.docker.com/v2/users/${h}/|
Dev.to|https://dev.to/${h}|
YouTube|https://www.youtube.com/@${h}|
SoundCloud|https://soundcloud.com/${h}|
Vimeo|https://vimeo.com/${h}|
Dribbble|https://dribbble.com/${h}|
Behance|https://www.behance.net/${h}|
Flickr|https://www.flickr.com/people/${h}/|
Linktree|https://linktr.ee/${h}|
About.me|https://about.me/${h}|
Gravatar|https://gravatar.com/${h}.json|
HackerOne|https://hackerone.com/${h}|
Mastodon|https://mastodon.social/@${h}|
X|https://x.com/${h}|
Hacker News|https://news.ycombinator.com/user?id=${h}|No such user
Steam|https://steamcommunity.com/id/${h}|could not be found
Bluesky|https://public.api.bsky.app/xrpc/com.atproto.identity.resolveHandle?handle=${h}.bsky.social|
EOF
}

social_check_one() {
  local label="$1" url="$2" marker="$3" timeout="$4"
  local code body result
  code=$(curl -sS -L -m "$timeout" -A "$USER_AGENT" -o /dev/null \
    -w '%{http_code}' -- "$url" 2>/dev/null || true)
  [[ "$code" =~ ^[0-9]{3}$ ]] || code='000'
  case "$code" in
    # Bluesky answers 400 when a handle does not resolve.
    200)          result='found' ;;
    400|404|410)  result='missing' ;;
    *)            result='unknown' ;;
  esac
  # Some sites return 200 for every name and explain the miss in the page.
  if [[ "$result" == 'found' && -n "$marker" ]]; then
    body=$(curl -sS -L -m "$timeout" -A "$USER_AGENT" -- "$url" 2>/dev/null \
      | head -c 200000 || true)
    if printf '%s' "$body" | grep -qiE -- "$marker"; then
      result='missing'
    fi
  fi
  printf '%s\t%s\t%s\t%s\n' "$label" "$url" "$code" "$result"
}

social_check_all() {
  local timeout="$1" conc="$2"
  shift 2
  local -a pids=()
  local line label url marker
  for line in "$@"; do
    IFS='|' read -r label url marker <<< "$line"
    social_check_one "$label" "$url" "$marker" "$timeout" &
    pids+=($!)
    if (( ${#pids[@]} >= conc )); then
      wait "${pids[0]}" 2>/dev/null || true
      pids=("${pids[@]:1}")
    fi
  done
  wait 2>/dev/null || true
}

mod_social() {
  local target='' handle='' timeout=12 conc=8 verbose=0

  while (( $# > 0 )); do
    case "$1" in
      --handle)      handle="${2:-}"; shift 2 || shift ;;
      --timeout)     timeout="${2:-12}"; shift 2 || shift ;;
      --concurrency) conc="${2:-8}"; shift 2 || shift ;;
      --verbose)     verbose=1; shift ;;
      -h|--help)
        printf 'usage: digger.sh social <handle|domain> [--handle NAME] [--timeout SEC] [--concurrency N] [--verbose]\n'
        return 0 ;;
      *)
        if [[ -z "$target" ]]; then target="$1"; fi
        shift ;;
    esac
  done

  heading "SOCIAL FOOTPRINT"
  hr 60

  if [[ -z "$target" && -z "$handle" ]]; then
    target=$(prompt "Username or domain")
  fi

  [[ "$timeout" =~ ^[0-9]+$ ]] && (( timeout > 0 )) || timeout=12
  [[ "$conc" =~ ^[0-9]+$ ]] && (( conc > 0 )) || conc=8

  local derived=0 t
  if [[ -z "$handle" ]]; then
    t="${target// /}"
    t="${t#*://}"
    t="${t%%/*}"
    t="${t%%:*}"
    t="${t%.}"
    t="${t,,}"
    if [[ -z "$t" ]]; then
      err "no handle given"
      return 1
    fi
    if [[ "$t" == *.* ]] && is_hostname "$t"; then
      t="${t#www.}"
      handle="${t%%.*}"
      derived=1
    else
      handle="$t"
    fi
  fi

  if [[ ! "$handle" =~ ^[A-Za-z0-9._-]{1,64}$ ]]; then
    err "invalid handle: ${handle}"
    return 1
  fi

  local platforms_raw
  platforms_raw=$(social_platforms "$handle")
  local -a platforms=()
  mapfile -t platforms < <(printf '%s\n' "$platforms_raw" | grep -v '^$' || true)

  info "Handle: ${C_BOLD}${handle}${C_RESET}"
  if (( derived )); then
    printf '  Derived     : from the domain, pass --handle to check someone else\n'
  fi
  printf '  Platforms   : %s %s(public profile pages, no login)%s\n' \
    "${#platforms[@]}" "$C_DIM" "$C_RESET"

  printf '\n  %schecking %s platforms...%s\n' "$C_DIM" "${#platforms[@]}" "$C_RESET"
  local raw
  raw=$(social_check_all "$timeout" "$conc" "${platforms[@]}")

  local -A res_state=() res_code=()
  local label url marker code state
  while IFS=$'\t' read -r label url code state; do
    [[ -z "$label" ]] && continue
    res_state["$label"]="$state"
    res_code["$label"]="$code"
  done <<< "$raw"

  local -a found=() missing=() unknown=()
  while IFS='|' read -r label url marker || [[ -n "$label" ]]; do
    [[ -z "$label" ]] && continue
    state="${res_state[$label]:-unknown}"
    code="${res_code[$label]:-000}"
    case "$state" in
      found)   found+=("${label}|${url}|${code}") ;;
      missing) missing+=("${label}|${url}|${code}") ;;
      *)       unknown+=("${label}|${url}|${code}") ;;
    esac
  done <<< "$platforms_raw"

  local item l u c names

  printf '\n%sFound%s (%s)\n' "$C_GREEN" "$C_RESET" "${#found[@]}"
  if (( ${#found[@]} == 0 )); then
    printf '  %snothing under this handle%s\n' "$C_DIM" "$C_RESET"
  fi
  for item in ${found[@]+"${found[@]}"}; do
    IFS='|' read -r l u c <<< "$item"
    printf '  %s%-12s%s %s\n' "$C_GREEN" "$l" "$C_RESET" "$u"
  done

  printf '\n%sNot found%s (%s)\n' "$C_DIM" "$C_RESET" "${#missing[@]}"
  if (( verbose )); then
    for item in ${missing[@]+"${missing[@]}"}; do
      IFS='|' read -r l u c <<< "$item"
      printf '  %-12s %-52s %s\n' "$l" "$u" "$c"
    done
  elif (( ${#missing[@]} > 0 )); then
    names=''
    for item in "${missing[@]}"; do
      names="${names}${item%%|*}, "
    done
    printf '%s\n' "${names%, }" | fold -s -w 72 | sed -E 's/[[:space:]]+$//; s/^/  /'
  else
    printf '  none\n'
  fi

  if (( ${#unknown[@]} > 0 )); then
    printf '\n%sBlocked or unverifiable%s (%s)\n' "$C_YELLOW" "$C_RESET" "${#unknown[@]}"
    for item in "${unknown[@]}"; do
      IFS='|' read -r l u c <<< "$item"
      printf '  %-12s %-52s %s\n' "$l" "$u" "$c"
    done
    printf '  %srate limits and login walls, try again later%s\n' "$C_DIM" "$C_RESET"
  fi

  printf '\n%sSummary%s\n' "$C_BOLD" "$C_RESET"
  printf '  Handle   : %s\n' "$handle"
  printf '  Checked  : %s\n' "${#platforms[@]}"
  printf '  Found    : %s\n' "${#found[@]}"
  printf '  Missing  : %s\n' "${#missing[@]}"
  printf '  Unknown  : %s\n' "${#unknown[@]}"
  return 0
}

# --- Module 15: Search Dork Generator --------------------------------------
# Build search engine queries from a domain. Purely offline, nothing is sent.
DORK_CATS=(files config panels leaks errors docs hosts)

dorks_title() {
  case "$1" in
    files)   printf 'Files and documents' ;;
    config)  printf 'Config and secrets' ;;
    panels)  printf 'Admin panels and listings' ;;
    leaks)   printf 'Leaks and third party' ;;
    errors)  printf 'Errors and stack traces' ;;
    docs)    printf 'Internal documents' ;;
    hosts)   printf 'Hosts and environments' ;;
    *)       printf '%s' "$1" ;;
  esac
}

dorks_queries() {
  local d="$1"
  cat <<EOF
files	site:${d} filetype:pdf
files	site:${d} filetype:xls OR filetype:xlsx
files	site:${d} filetype:doc OR filetype:docx
files	site:${d} filetype:ppt OR filetype:pptx
files	site:${d} filetype:csv
files	site:${d} filetype:sql
files	site:${d} filetype:log
files	site:${d} filetype:bak OR filetype:old
config	site:${d} ext:env
config	site:${d} ext:ini OR ext:cfg
config	site:${d} ext:yaml OR ext:yml
config	site:${d} ext:json "api_key"
config	site:${d} ext:xml "password"
config	site:${d} "DB_PASSWORD"
config	site:${d} "BEGIN RSA PRIVATE KEY"
panels	site:${d} inurl:admin
panels	site:${d} inurl:login OR inurl:signin
panels	site:${d} inurl:wp-admin
panels	site:${d} inurl:phpmyadmin
panels	site:${d} inurl:dashboard
panels	site:${d} intitle:"index of"
panels	site:${d} inurl:"/.git"
leaks	"${d}" site:pastebin.com
leaks	"${d}" site:github.com
leaks	"${d}" site:gitlab.com
leaks	"${d}" filetype:txt password
leaks	site:${d} inurl:password
leaks	site:${d} inurl:token OR inurl:apikey
leaks	"@${d}" -site:${d}
errors	site:${d} "SQL syntax.*MySQL"
errors	site:${d} "Warning: mysql_"
errors	site:${d} "Fatal error"
errors	site:${d} "stack trace"
errors	site:${d} "Uncaught exception"
docs	site:${d} "confidential"
docs	site:${d} "internal use only"
docs	site:${d} filetype:pdf "not for distribution"
docs	site:${d} intitle:"employee handbook"
hosts	site:*.${d}
hosts	site:${d} -www
hosts	site:${d} inurl:dev OR inurl:staging OR inurl:test
hosts	site:${d} inurl:api
EOF
}

dorks_engine_url() {
  local engine="$1" query="$2" encoded
  case "$engine" in
    bing)       encoded=$(urlencode_q "$query"); printf 'https://www.bing.com/search?q=%s' "$encoded" ;;
    duckduckgo) encoded=$(urlencode_q "$query"); printf 'https://duckduckgo.com/?q=%s' "$encoded" ;;
    brave)      encoded=$(urlencode_q "$query"); printf 'https://search.brave.com/search?q=%s' "$encoded" ;;
    *)          encoded=$(urlencode_q "$query"); printf 'https://www.google.com/search?q=%s' "$encoded" ;;
  esac
}

mod_dorks() {
  local target='' only='' engine='google'
  local links=0

  while (( $# > 0 )); do
    case "$1" in
      --category) only="${2:-}"; shift 2 || shift ;;
      --engine)   engine="${2:-google}"; shift 2 || shift ;;
      --links)    links=1; shift ;;
      -h|--help)
        printf 'usage: digger.sh dorks <domain> [--category NAME] [--engine google|bing|duckduckgo|brave] [--links]\n'
        printf 'categories: %s\n' "${DORK_CATS[*]}"
        return 0 ;;
      *)
        if [[ -z "$target" ]]; then target="$1"; fi
        shift ;;
    esac
  done

  heading "SEARCH DORK GENERATOR"
  hr 60

  if [[ -z "$target" ]]; then
    target=$(prompt "Domain")
  fi
  target="${target// /}"
  if [[ -z "$target" ]]; then
    err "no domain given"
    return 1
  fi
  target="${target#*://}"
  target="${target%%/*}"
  target="${target%%:*}"
  target="${target%.}"
  target="${target,,}"
  if ! is_hostname "$target" && ! is_ip "$target"; then
    err "invalid domain: ${target}"
    return 1
  fi

  case "${engine,,}" in
    google|bing|duckduckgo|brave) engine="${engine,,}" ;;
    *) err "unknown engine: ${engine} (try google, bing, duckduckgo or brave)"; return 1 ;;
  esac

  local valid=0 c
  if [[ -n "$only" ]]; then
    only="${only,,}"
    for c in "${DORK_CATS[@]}"; do
      [[ "$c" == "$only" ]] && valid=1
    done
    if (( valid == 0 )); then
      err "unknown category: ${only} (try ${DORK_CATS[*]})"
      return 1
    fi
  fi

  local rows total
  rows=$(dorks_queries "$target")
  total=0
  while IFS=$'\t' read -r c _ || [[ -n "$c" ]]; do
    [[ -z "$c" ]] && continue
    if [[ -n "$only" && "$c" != "$only" ]]; then
      continue
    fi
    total=$((total + 1))
  done <<< "$rows"

  info "Target: ${C_BOLD}${target}${C_RESET}"
  printf '  Categories  : %s\n' "${#DORK_CATS[@]}"
  [[ -n "$only" ]] && printf '  Filter      : %s\n' "$only"
  printf '  Queries     : %s\n' "$total"
  printf '  Engine      : %s %s(add --links for search urls)%s\n' \
    "$engine" "$C_DIM" "$C_RESET"

  local -a items=()
  local q n
  for c in "${DORK_CATS[@]}"; do
    if [[ -n "$only" && "$only" != "$c" ]]; then
      continue
    fi
    items=()
    while IFS=$'\t' read -r cat q || [[ -n "$cat" ]]; do
      [[ "$cat" == "$c" ]] && items+=("$q")
    done <<< "$rows"
    (( ${#items[@]} == 0 )) && continue

    printf '\n%s%s%s (%s)\n' "$C_BOLD" "$(dorks_title "$c")" "$C_RESET" "${#items[@]}"
    for q in "${items[@]}"; do
      printf '  %s\n' "$q"
      if (( links )); then
        printf '    %s%s%s\n' "$C_DIM" "$(dorks_engine_url "$engine" "$q")" "$C_RESET"
      fi
    done
  done

  printf '\n%sSummary%s\n' "$C_BOLD" "$C_RESET"
  printf '  Target   : %s\n' "$target"
  printf '  Queries  : %s\n' "$total"
  printf '  %sresults depend on the engine: check each hit before trusting it%s\n' \
    "$C_DIM" "$C_RESET"
  return 0
}

# --- Module 9: Historical Snapshots ----------------------------------------
WAYBACK_CDX='https://web.archive.org/cdx/search/cdx'

# CDX rows: one 14 digit timestamp per record. Status codes are optional
# ("-"), so the timeline query asks for timestamps only.
archive_rows() {
  grep -oE '"[0-9]{14}"' | tr -d '"' || true
}

# Recent captures also carry a status and the original URL.
archive_rows_full() {
  grep -oE '"[0-9]{14}","[^"]*","[^"]*"' \
    | sed -E 's/"([0-9]{14})","([^"]*)","([^"]*)"/\1\t\2\t\3/' || true
}

# 20020120142510 -> 2002-01-20 14:25:10
archive_stamp() {
  local t="$1"
  if [[ "$t" =~ ^([0-9]{4})([0-9]{2})([0-9]{2})([0-9]{2})([0-9]{2})([0-9]{2})$ ]]; then
    printf '%s-%s-%s %s:%s:%s' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" \
      "${BASH_REMATCH[3]}" "${BASH_REMATCH[4]}" "${BASH_REMATCH[5]}" "${BASH_REMATCH[6]}"
  else
    printf '%s' "$t"
  fi
}

mod_archive() {
  local target='' limit=20000 recent=10 subdomains=0
  local status='' from='' to='' year=''

  while (( $# > 0 )); do
    case "$1" in
      --limit)      limit="${2:-20000}"; shift 2 || shift ;;
      --recent)     recent="${2:-10}"; shift 2 || shift ;;
      --subdomains) subdomains=1; shift ;;
      --status)     status="${2:-}"; shift 2 || shift ;;
      --from)       from="${2:-}"; shift 2 || shift ;;
      --to)         to="${2:-}"; shift 2 || shift ;;
      --year)       year="${2:-}"; shift 2 || shift ;;
      -h|--help)
        printf 'usage: digger.sh archive <domain|url> [--year YYYY] [--from STAMP] [--to STAMP] [--status CODE] [--subdomains] [--limit N] [--recent N]\n'
        return 0 ;;
      *)
        if [[ -z "$target" ]]; then target="$1"; fi
        shift ;;
    esac
  done

  heading "HISTORICAL SNAPSHOTS"
  hr 60

  if [[ -z "$target" ]]; then
    target=$(prompt "Domain or URL")
  fi
  target="${target// /}"
  if [[ -z "$target" ]]; then
    err "no target given"
    return 1
  fi
  target="${target#*://}"
  target="${target%%#*}"
  target="${target%%\?*}"
  target="${target%/}"

  local host="${target%%/*}"
  host="${host%%:*}"
  if ! is_hostname "$host" && ! is_ip "$host"; then
    err "invalid target: ${target}"
    return 1
  fi

  [[ "$limit" =~ ^[0-9]+$ ]] && (( limit > 0 )) || limit=20000
  [[ "$recent" =~ ^[0-9]+$ ]] && (( recent > 0 )) || recent=10
  [[ "$status" =~ ^[0-9]{3}$ ]] || status=''
  [[ "$from" =~ ^[0-9]{4,14}$ ]] || from=''
  [[ "$to" =~ ^[0-9]{4,14}$ ]] || to=''

  if [[ -n "$year" ]]; then
    if [[ "$year" =~ ^[0-9]{4}$ ]]; then
      [[ -z "$from" ]] && from="${year}0101"
      [[ -z "$to" ]] && to="${year}1231"
    else
      err "invalid year: ${year}"
      return 1
    fi
  fi

  local query="url=${target}&output=json&collapse=timestamp:8"
  (( subdomains )) && query="${query}&matchType=domain"
  [[ -n "$status" ]] && query="${query}&filter=statuscode:${status}"
  [[ -n "$from" ]] && query="${query}&from=${from}"
  [[ -n "$to" ]] && query="${query}&to=${to}"

  info "Target: ${C_BOLD}${target}${C_RESET}"
  printf '  Source      : web.archive.org CDX %s(keyless, passive)%s\n' \
    "$C_DIM" "$C_RESET"
  (( subdomains )) && printf '  Scope       : the domain and every subdomain\n'
  [[ -n "$year" ]] && printf '  Year        : %s\n' "$year"

  printf '\n  %squerying the wayback index...%s\n' "$C_DIM" "$C_RESET"
  local json1
  json1=$(http_get "${WAYBACK_CDX}?${query}&fl=timestamp&limit=${limit}" 60 0) || json1=''

  if [[ -z "$json1" || "$json1" == '[]' ]]; then
    warn "no captures found for ${target}"
    printf '  %snothing archived, or the index is rate limiting right now%s\n' \
      "$C_DIM" "$C_RESET"
    return 0
  fi
  if [[ "$json1" != \[* ]]; then
    warn "the wayback index did not return JSON (rate limited or unavailable)"
    return 1
  fi

  local timeline total first_ts last_ts tl
  timeline=$(printf '%s\n' "$json1" | archive_rows)
  total=$(printf '%s\n' "$timeline" | grep -c . || true)
  if (( ${total:-0} == 0 )); then
    warn "no captures found for ${target}"
    return 0
  fi
  # Avoid head/tail here: piping a large variable into them raises SIGPIPE,
  # and pipefail would take the whole script down with it.
  tl="${timeline%$'\n'}"
  first_ts="${tl%%$'\n'*}"
  first_ts="${first_ts%%$'\t'*}"
  last_ts="${tl##*$'\n'}"
  last_ts="${last_ts%%$'\t'*}"

  # --- availability -------------------------------------------------------
  # The availability endpoint ignores the CDX time filters, so only ask when
  # the report covers the full history.
  local avail closest_url='' closest_ts='' closest_status=''
  if [[ -z "$from" && -z "$to" ]]; then
    avail=$(http_get "https://archive.org/wayback/available?url=${target}" 20 1) || avail=''
    if [[ -n "$avail" ]]; then
      closest_url=$(json_get "$avail" '.archived_snapshots.closest.url' 2>/dev/null || true)
      closest_ts=$(json_get "$avail" '.archived_snapshots.closest.timestamp' 2>/dev/null || true)
      closest_status=$(json_get "$avail" '.archived_snapshots.closest.status' 2>/dev/null || true)
    fi
  fi

  printf '\n%sCoverage%s\n' "$C_BOLD" "$C_RESET"
  printf '  first capture : %s\n' "$(archive_stamp "$first_ts")"
  printf '  last capture  : %s\n' "$(archive_stamp "$last_ts")"
  printf '  days archived : %s\n' "$total"
  printf '  span          : %s - %s\n' "${first_ts:0:4}" "${last_ts:0:4}"
  if [[ -n "$closest_url" ]]; then
    printf '  closest       : %s (%s)\n' "$(archive_stamp "$closest_ts")" "${closest_status:-?}"
    printf '    %s%s%s\n' "$C_DIM" "$closest_url" "$C_RESET"
  fi
  if (( total >= limit )); then
    printf '  %scapped at %s days, raise --limit for the full history%s\n' \
      "$C_DIM" "$limit" "$C_RESET"
  fi

  # --- timeline -----------------------------------------------------------
  local year_counts
  year_counts=$(printf '%s\n' "$timeline" | cut -f1 | cut -c1-4 \
    | sort | uniq -c | awk '{print $2"\t"$1}')

  local max=0 y n bar len
  while IFS=$'\t' read -r y n || [[ -n "$y" ]]; do
    [[ -z "$y" ]] && continue
    (( n > max )) && max=$n
  done <<< "$year_counts"

  printf '\n%sDays archived per year%s\n' "$C_BOLD" "$C_RESET"
  while IFS=$'\t' read -r y n || [[ -n "$y" ]]; do
    [[ -z "$y" ]] && continue
    len=0
    if (( max > 0 )); then
      len=$(( n * 28 / max ))
    fi
    (( n > 0 && len < 1 )) && len=1
    bar=$(printf '%*s' "$len" '' | tr ' ' '#')
    printf '  %s  %-28s %s\n' "$y" "$bar" "$n"
  done <<< "$year_counts"

  # --- recent captures ----------------------------------------------------
  local json2 rows2
  json2=$(http_get "${WAYBACK_CDX}?${query}&fl=timestamp,statuscode,original&limit=-${recent}" 60 0) || json2=''
  rows2=$(printf '%s\n' "$json2" | archive_rows_full)

  if [[ -n "$rows2" ]]; then
    printf '\n%sRecent captures%s\n' "$C_BOLD" "$C_RESET"
    local ts code orig
    while IFS=$'\t' read -r ts code orig; do
      [[ -z "$ts" ]] && continue
      printf '  %s  %s  %s\n' "$(archive_stamp "$ts")" "$code" "$orig"
      printf '    %shttps://web.archive.org/web/%s/%s%s\n' \
        "$C_DIM" "$ts" "$orig" "$C_RESET"
    done <<< "$rows2"
  fi

  # --- summary ------------------------------------------------------------
  printf '\n%sSummary%s\n' "$C_BOLD" "$C_RESET"
  printf '  Target    : %s\n' "$target"
  printf '  Captures  : %s days\n' "$total"
  printf '  Range     : %s to %s\n' "${first_ts:0:4}" "${last_ts:0:4}"
  [[ -n "$closest_url" ]] && printf '  Closest   : %s\n' "$closest_url"
  printf '  %sarchived copies often expose old paths, parameters and source%s\n' \
    "$C_DIM" "$C_RESET"
  return 0
}

# --- Module 10: Common Paths ----------------------------------------------
# Probe a single path. Prints one tab separated line so parallel probes can
# be merged without interleaving.
paths_probe_one() {
  local base="$1" path="$2" timeout="$3" follow="$4"
  local -a cargs=(-s -o /dev/null -k --max-time "$timeout" --max-filesize 2097152
                  -H "User-Agent: $USER_AGENT"
                  -w '%{http_code}\t%{size_download}\t%{content_type}')
  (( follow )) && cargs+=(-L)
  local out='' code size ctype rest
  out=$(curl "${cargs[@]}" -- "${base}${path}" 2>/dev/null || true)
  [[ -z "$out" ]] && out=$'000\t0\t-'
  code="${out%%$'\t'*}"
  rest="${out#*$'\t'}"
  size="${rest%%$'\t'*}"
  ctype="${rest#*$'\t'}"
  [[ -z "$ctype" ]] && ctype='-'
  printf '%s\t%s\t%s\t%s\n' "$code" "$size" "$ctype" "$path"
}

# Probe every path in the wordlist, keeping at most <conc> requests in flight.
paths_probe_all() {
  local base="$1" wl="$2" conc="$3" timeout="$4" follow="$5"
  local -a pids=()
  local path
  while IFS= read -r path || [[ -n "$path" ]]; do
    path="${path%$'\r'}"
    [[ -z "$path" ]] && continue
    [[ "$path" == \#* ]] && continue
    [[ "$path" != /* ]] && path="/${path}"
    paths_probe_one "$base" "$path" "$timeout" "$follow" &
    pids+=($!)
    if (( ${#pids[@]} >= conc )); then
      wait "${pids[0]}" 2>/dev/null || true
      pids=("${pids[@]:1}")
    fi
  done < "$wl"
  wait 2>/dev/null || true
}

mod_paths() {
  local target="" wordlist='' conc=10 timeout=10 follow=1

  while (( $# > 0 )); do
    case "$1" in
      --wordlist)    wordlist="${2:-}"; shift 2 || shift ;;
      --concurrency) conc="${2:-10}"; shift 2 || shift ;;
      --timeout)     timeout="${2:-10}"; shift 2 || shift ;;
      --no-follow)   follow=0; shift ;;
      -y|--yes)      ASSUME_YES=1; shift ;;
      -h|--help)
        printf 'usage: digger.sh paths <url> [--wordlist FILE] [--concurrency N] [--timeout SEC] [--no-follow]\n'
        return 0 ;;
      *)
        if [[ -z "$target" ]]; then target="$1"; fi
        shift ;;
    esac
  done

  heading "COMMON PATHS"
  hr 60

  if [[ -z "$target" ]]; then
    target=$(prompt "Target URL or host")
  fi
  target="${target// /}"
  if [[ -z "$target" ]]; then
    err "no target given"
    return 1
  fi

  # --- work out the base URL ----------------------------------------------
  local base="$target" scheme=''
  if [[ "$target" != http://* && "$target" != https://* ]]; then
    scheme='https'
  else
    scheme="${target%%://*}"
    base="$target"
  fi
  base="${base%/}"
  local hostpart="${base#*://}"
  hostpart="${hostpart%%/*}"
  if ! is_hostname "$hostpart" && ! is_ip "$hostpart"; then
    err "invalid target: ${target}"
    return 1
  fi

  # Prefer whichever scheme actually answers.
  local code
  code=$(final_status "$base" 12)
  if [[ ! "$code" =~ ^[1-5] ]] && [[ "$scheme" == 'https' ]]; then
    local alt="http://${base#https://}"
    if [[ "$(final_status "$alt" 12)" =~ ^[1-5] ]]; then
      base="$alt"
    fi
  fi

  info "Target: ${C_BOLD}${base}${C_RESET}"

  # --- wordlist -----------------------------------------------------------
  if [[ -z "$wordlist" ]]; then
    wordlist=$(wordlist_file "paths.txt" || true)
  fi
  if [[ -z "$wordlist" || ! -f "$wordlist" ]]; then
    err "no wordlist found (looked for wordlist/paths.txt)"
    return 1
  fi

  local count
  count=$(grep -cvE '^\s*(#|$)' "$wordlist" || true)
  [[ "$count" =~ ^[0-9]+$ ]] || count=0

  printf '  Wordlist   : %s (%s paths)\n' "$wordlist" "$count"
  printf '  Concurrency: %s   Timeout: %ss\n' "$conc" "$timeout"

  # --- confirmation -------------------------------------------------------
  if ! confirm "This sends ${count} active requests to ${base}. Continue?"; then
    warn "aborted"
    return 0
  fi

  local raw
  raw=$(paths_probe_all "$base" "$wordlist" "$conc" "$timeout" "$follow")

  # --- baseline (soft 404) detection ---------------------------------------
  local top base_code='' base_size=''
  top=$(printf '%s\n' "$raw" | awk -F'\t' 'NF>=2{print $1" "$2}' | sort | uniq -c | sort -rn | head -n1 || true)
  if [[ -n "$top" ]]; then
    base_code=$(printf '%s' "$top" | awk '{print $2}')
    base_size=$(printf '%s' "$top" | awk '{print $3}')
  fi

  local -a found=() interesting=() soft=() missing=()
  local line code size ctype path
  while IFS=$'\t' read -r code size ctype path; do
    [[ -z "$path" ]] && continue
    case "$code" in
      2*|3*) found+=("${code}|${size}|${ctype}|${path}") ;;
      401|403|405) interesting+=("${code}|${size}|${ctype}|${path}") ;;
      *)
        if [[ -n "$base_code" && "$code" == "$base_code" && "$size" == "$base_size" ]]; then
          soft+=("${code}|${size}|${ctype}|${path}")
        else
          missing+=("${code}|${size}|${ctype}|${path}")
        fi
        ;;
    esac
  done <<< "$raw"

  printf '\n%sResults%s\n' "$C_BOLD" "$C_RESET"
  printf '  Probed %s paths, %s responded\n\n' "$count" "$((${#found[@]} + ${#interesting[@]} + ${#soft[@]} + ${#missing[@]}))"

  local -a group
  local title colour
  for spec in "found:${C_GREEN}" "interesting:${C_YELLOW}" "soft:${C_DIM}" "missing:${C_DIM}"; do
    title="${spec%%:*}"
    colour="${spec#*:}"
    case "$title" in
      found)      group=("${found[@]}") ;;
      interesting) group=("${interesting[@]}") ;;
      soft)       group=("${soft[@]}") ;;
      missing)    group=("${missing[@]}") ;;
    esac
    (( ${#group[@]} == 0 )) && continue
    case "$title" in
      found)       label="Found" ;;
      interesting) label="Interesting" ;;
      soft)        label="Not found (soft 404 baseline)" ;;
      missing)     label="Other responses" ;;
    esac
    printf '%s%s%s (%s)\n' "$colour" "$label" "$C_RESET" "${#group[@]}"
    local entry c s t p shown=0
    for entry in "${group[@]}"; do
      (( shown >= 30 )) && break
      IFS='|' read -r c s t p <<< "$entry"
      printf '  %s%-5s%s %-34s %10s  %s\n' "$colour" "$c" "$C_RESET" "$p" "$(human_size "$s")" "$t"
      shown=$((shown + 1))
    done
    if (( ${#group[@]} > shown )); then
      printf '  %s... and %s more%s\n' "$C_DIM" "$((${#group[@]} - shown))" "$C_RESET"
    fi
    printf '\n'
  done
  return 0
}

read -r -d '' PY_PARSE_DATE <<'PYEOF' || true
import sys, time, calendar
try:
    sys.stdout.reconfigure(newline='\n')
except Exception:
    pass
s = sys.argv[1].strip()
if s.endswith('GMT'):
    s = s[:-3].strip()
for fmt in ('%b %d %H:%M:%S %Y', '%b %d %H:%M:%S %Y %Z', '%Y-%m-%dT%H:%M:%S'):
    try:
        print(int(calendar.timegm(time.strptime(s, fmt))))
        break
    except Exception:
        continue
PYEOF

# Days between now and a certificate notAfter date. Negative means expired.
tls_days_until() {
  local enddate="$1" end_epoch='' now
  now=$(date +%s 2>/dev/null || printf '0')
  end_epoch=$(date -d "$enddate" +%s 2>/dev/null || true)
  if [[ -z "$end_epoch" ]] && [[ -n "$PY" ]]; then
    end_epoch=$("$PY" -c "$PY_PARSE_DATE" "$enddate" 2>/dev/null || true)
  fi
  [[ -z "$end_epoch" ]] && return 1
  printf '%s' "$(( (end_epoch - now) / 86400 ))"
}

# Raw openssl handshake output for a host and port.
tls_handshake() {
  local host="$1" port="$2" extra="${3:-}"
  # shellcheck disable=SC2086
  timeout 20 openssl s_client -connect "${host}:${port}" -servername "$host" $extra </dev/null 2>/dev/null || true
}

# The leaf certificate, PEM encoded.
tls_leaf_cert() {
  local host="$1" port="$2"
  tls_handshake "$host" "$port" "-showcerts" \
    | awk '/-----BEGIN CERTIFICATE-----/{f=1} f{print} /-----END CERTIFICATE-----/{exit}'
}

# Test one protocol version. Local OpenSSL builds often disable TLS 1.0 and
# 1.1 at the default security level, so retry with the level lowered before
# declaring the protocol unsupported.
tls_protocol_test() {
  local host="$1" port="$2" flag="$3" out=''
  out=$(timeout 15 openssl s_client -connect "${host}:${port}" -servername "$host" "-${flag}" </dev/null 2>&1 || true)
  if printf '%s' "$out" | grep -q 'no protocols available\|no ciphers available'; then
    out=$(timeout 15 openssl s_client -connect "${host}:${port}" -servername "$host" "-${flag}" \
      -cipher 'ALL:@SECLEVEL=0' </dev/null 2>&1 || true)
  fi
  printf '%s' "$out"
}

# Extract the negotiated cipher from an openssl handshake dump. OpenSSL 3.x
# prints it in the session block for TLS 1.2 and older, and in the handshake
# summary line for TLS 1.3.
tls_cipher_of() {
  local out="$1" c=''
  c=$(printf '%s' "$out" | grep -m1 '^ *Cipher *:' | sed -E 's/^ *Cipher *: *//' || true)
  if [[ -z "$c" || "$c" == '0000' || "$c" == '(NONE)' ]]; then
    c=$(printf '%s' "$out" | grep -m1 'Cipher is ' | sed -E 's/.*Cipher is //' || true)
  fi
  [[ "$c" == '0000' || "$c" == '(NONE)' ]] && c=''
  printf '%s' "$c"
}

tls_proto_of() {
  local out="$1" p=''
  p=$(printf '%s' "$out" | grep -m1 '^ *Protocol *:' | sed -E 's/^ *Protocol *: *//' || true)
  printf '%s' "$p"
}

# Does the subject alternative name list cover this host?
tls_covers_host() {
  local san="$1" host="$2" n suffix
  while IFS= read -r n; do
    [[ -z "$n" ]] && continue
    if [[ "$n" == "$host" ]]; then return 0; fi
    if [[ "$n" == '*.'* ]]; then
      suffix="${n#*.}"
      if [[ "$host" == *".${suffix}" ]]; then return 0; fi
    fi
  done < <(printf '%s' "$san" | tr ',' '\n' \
    | sed -E 's/^[[:space:]]*DNS://I; s/^[[:space:]]*//; s/[[:space:]]*$//')
  return 1
}

# --- Module 11: TLS Inspector ----------------------------------------------
mod_tls() {
  local target='' port=443

  while (( $# > 0 )); do
    case "$1" in
      --port) port="${2:-443}"; shift 2 || shift ;;
      -h|--help)
        printf 'usage: digger.sh tls <host[:port]>\n'
        return 0 ;;
      *)
        if [[ -z "$target" ]]; then target="$1"; fi
        shift ;;
    esac
  done

  heading "TLS INSPECTOR"
  hr 60

  if [[ -z "$target" ]]; then
    target=$(prompt "Host")
  fi
  target="${target// /}"
  target="${target,,}"

  if [[ -z "$target" ]]; then
    err "no target given"
    return 1
  fi

  local host="$target"
  if [[ "$host" == *:* && "$host" != *:*:* ]]; then
    port="${host##*:}"
    host="${host%:*}"
  fi
  if ! is_hostname "$host" && ! is_ip "$host"; then
    err "invalid host: ${target}"
    return 1
  fi
  if ! [[ "$port" =~ ^[0-9]+$ ]] || (( port < 1 || port > 65535 )); then
    err "invalid port: ${port}"
    return 1
  fi

  if ! have openssl; then
    err "openssl is required for the TLS inspector"
    return 1
  fi

  info "Target: ${C_BOLD}${host}:${port}${C_RESET}"

  local chain
  chain=$(tls_handshake "$host" "$port" "-showcerts")
  if [[ -z "$chain" ]] || ! printf '%s' "$chain" | grep -q 'BEGIN CERTIFICATE'; then
    err "no TLS service on ${host}:${port}"
    return 1
  fi

  # --- connection ---------------------------------------------------------
  local proto cipher chain_len
  proto=$(tls_proto_of "$chain")
  cipher=$(tls_cipher_of "$chain")
  chain_len=$(printf '%s' "$chain" | grep -c -- '-----BEGIN CERTIFICATE' || true)

  printf '\n%sConnection%s\n' "$C_BOLD" "$C_RESET"
  printf '  Protocol        : %s\n' "${proto:-unknown}"
  printf '  Cipher          : %s\n' "${cipher:-unknown}"
  printf '  Chain length    : %s\n' "$chain_len"
  printf '  Local OpenSSL   : %s\n' "$(openssl version 2>/dev/null | awk '{print $1" "$2}' || echo unknown)"

  # --- leaf certificate ---------------------------------------------------
  local cert
  cert=$(tls_leaf_cert "$host" "$port")
  if [[ -z "$cert" ]]; then
    warn "could not read the leaf certificate"
    return 0
  fi

  local subject issuer notbefore notafter serial fp keyinfo sigalg san certtext
  subject=$(printf '%s' "$cert" | openssl x509 -noout -subject 2>/dev/null | sed 's/^subject=//; s/^ *//' || true)
  issuer=$(printf '%s' "$cert" | openssl x509 -noout -issuer 2>/dev/null | sed 's/^issuer=//; s/^ *//' || true)
  notbefore=$(printf '%s' "$cert" | openssl x509 -noout -startdate 2>/dev/null | sed 's/^notBefore=//' || true)
  notafter=$(printf '%s' "$cert" | openssl x509 -noout -enddate 2>/dev/null | sed 's/^notAfter=//' || true)
  serial=$(printf '%s' "$cert" | openssl x509 -noout -serial 2>/dev/null | sed 's/^serial=//' || true)
  fp=$(printf '%s' "$cert" | openssl x509 -noout -fingerprint -sha256 2>/dev/null | sed 's/^.*=//' || true)
  certtext=$(printf '%s' "$cert" | openssl x509 -noout -text 2>/dev/null || true)
  keyinfo=$(printf '%s' "$certtext" | grep -m1 -i 'Public-Key:' | sed 's/^ *//' || true)
  sigalg=$(printf '%s' "$certtext" | grep -m1 -i 'Signature Algorithm:' | sed 's/^ *//' || true)
  san=$(printf '%s' "$cert" | openssl x509 -noout -ext subjectAltName 2>/dev/null | tail -n1 | sed 's/^ *//' || true)

  # friendlier key description
  local keydesc="$keyinfo"
  if printf '%s' "$certtext" | grep -qi 'id-ecPublicKey'; then
    keydesc="EC $(printf '%s' "$keyinfo" | grep -oE '[0-9]+ bit' || true)"
  elif printf '%s' "$certtext" | grep -qi 'rsaEncryption'; then
    keydesc="RSA $(printf '%s' "$keyinfo" | grep -oE '[0-9]+ bit' || true)"
  elif printf '%s' "$certtext" | grep -qi 'Ed25519\|Ed448'; then
    keydesc="EdDSA"
  fi
  local curve
  curve=$(printf '%s' "$certtext" | grep -m1 'ASN1 OID' | sed -E 's/^ *ASN1 OID: *//' || true)
  [[ -n "$curve" ]] && keydesc="${keydesc} (${curve})"

  printf '\n%sCertificate%s\n' "$C_BOLD" "$C_RESET"
  printf '  Subject         : %s\n' "${subject:-unknown}"
  printf '  Issuer          : %s\n' "${issuer:-unknown}"
  printf '  Valid from      : %s\n' "${notbefore:-unknown}"
  printf '  Valid until     : %s\n' "${notafter:-unknown}"
  printf '  Serial          : %s\n' "${serial:-unknown}"
  printf '  Key             : %s\n' "${keydesc:-unknown}"
  printf '  Signature alg   : %s\n' "${sigalg:-unknown}"
  printf '  SHA-256         : %s\n' "${fp:-unknown}"
  [[ -n "$san" ]] && printf '  SANs            : %s\n' "$san"

  local days=''
  days=$(tls_days_until "$notafter" || true)
  if [[ -n "$days" ]]; then
    if (( days < 0 )); then
      printf '  Expires in      : %sEXPIRED %s days ago%s\n' "$C_RED" "$((-days))" "$C_RESET"
    else
      printf '  Expires in      : %s days\n' "$days"
    fi
  fi

  # --- protocol matrix ----------------------------------------------------
  printf '\n%sProtocol support%s\n' "$C_BOLD" "$C_RESET"
  local -a flags=("tls1" "tls1_1" "tls1_2" "tls1_3")
  local -a names=("TLS 1.0" "TLS 1.1" "TLS 1.2" "TLS 1.3")
  local i out c
  for i in 0 1 2 3; do
    out=$(tls_protocol_test "$host" "$port" "${flags[$i]}")
    c=$(tls_cipher_of "$out")
    if [[ -n "$c" ]]; then
      printf '  %s[+]%s %-9s supported   %s\n' "$C_GREEN" "$C_RESET" "${names[$i]}" "$c"
    else
      printf '  %s[-]%s %-9s not supported\n' "$C_RED" "$C_RESET" "${names[$i]}"
    fi
  done

  # --- findings -----------------------------------------------------------
  printf '\n%sFindings%s\n' "$C_BOLD" "$C_RESET"
  if [[ -n "$days" ]]; then
    if (( days < 0 )); then
      printf '  %s[!]%s the certificate expired %s days ago\n' "$C_RED" "$C_RESET" "$((-days))"
    elif (( days < 15 )); then
      printf '  %s[!]%s the certificate expires in %s days\n' "$C_YELLOW" "$C_RESET" "$days"
    elif (( days < 30 )); then
      printf '  %s[!]%s the certificate expires in %s days\n' "$C_YELLOW" "$C_RESET" "$days"
    else
      printf '  %s[+]%s the certificate is valid for another %s days\n' "$C_GREEN" "$C_RESET" "$days"
    fi
  fi
  if printf '%s' "$subject" | grep -q '\*'; then
    printf '  %s[!]%s wildcard certificate\n' "$C_YELLOW" "$C_RESET"
  fi
  if printf '%s' "$sigalg" | grep -qi 'sha1\|md5'; then
    printf '  %s[!]%s weak signature algorithm: %s\n' "$C_RED" "$C_RESET" "$sigalg"
  fi
  if printf '%s' "$keyinfo" | grep -qi '1024'; then
    printf '  %s[!]%s small key: %s\n' "$C_RED" "$C_RESET" "$keyinfo"
  fi
  if [[ -z "$san" ]]; then
    printf '  %s[!]%s no subject alternative names\n' "$C_YELLOW" "$C_RESET"
  elif tls_covers_host "$san" "$host"; then
    printf '  %s[+]%s the certificate covers %s\n' "$C_GREEN" "$C_RESET" "$host"
  else
    printf '  %s[!]%s the certificate does not appear to cover %s\n' "$C_YELLOW" "$C_RESET" "$host"
  fi
  return 0
}

# --- Module 12: CDN and WAF Detection --------------------------------------
# Each row is: name|header list|cname pattern|issuer pattern|asn list
CDN_TABLE=(
  "Cloudflare|cf-ray,cf-cache-status,cf-connecting-ip,cf-request-id|cloudflare|cloudflare|13335,13336"
  "CloudFront|x-amz-cf-id,x-amz-cf-pop,via: 1.1 amazonaws|amazonaws|amazon|16509,14618"
  "Akamai|x-akamai-transformed,akamai-grn,x-akamai-features|akamaitechnologies|akamai|20940,16625,32787"
  "Fastly|x-fastly-request-id,fastly-io-info,x-fastly-pop|fastly|fastly|54113"
  "Azure CDN|x-azure-ref,x-msedge-ref,x-azure-cdn|azurefd,azureedge|azure|8075,8068"
  "Google Cloud CDN|x-goog-generation,google-apps|x.googleapis|googleusercontent|google|15169,16591"
  "Sucuri|x-sucuri-id,x-sucuri-cache|sucuri|sucuri|30177,39510"
  "Vercel|x-vercel-id,server: vercel|vercel-dns|vercel|16509"
  "Netlify|x-nf-request-id,server: netlify|netlify|netlify|10429,12389"
  "Bunny CDN|x-bunny-cache,bunny-cache|bunnycdn|bunny|42765,45812"
  "CDN77|x-cdn77,server: cd77|cdn77|cdn77|212238"
  "Imperva|incap_ses,x-iinfo|incap|imperva|207267"
  "StackPath|server: stackpath|stackpath|stackpath|47583"
  "CacheFly|x-cache: cachefly|cachefly|cachefly|3009"
  "KeyCDN|x-edge-location|keycdn|keycdn|20940"
)

# Each row is: name|header list|cookie fragment
WAF_TABLE=(
  "Cloudflare|cf-ray,cf-mitigated|x-cf-mitigated|_cf_bm"
  "AWS WAF|x-amzn-waf|awswaf"
  "Akamai|x-akamai-features|ak_bmsc"
  "Imperva / Incapsula|x-iinfo|incap_ses"
  "F5 BIG-IP|x-waf,bigipserver|BIGipServer"
  "Sucuri WAF|x-sucuri-id|SucuriCloudIDS"
  "Fortinet FortiWeb|x-fortiwaf|fortiwaf"
  "Barracuda|x-barracuda|barra_counter_session"
  "Wordfence|wfwaf|wfwaf-authcookie"
  "ModSecurity|server: mod_security,mod_security|x-mod-security"
  "Wallarm|x-wallarm|wallarm"
  "Palo Alto|server: panw|panw"
  "Radware|server: radware|x-radware"
)

mod_cdn() {
  local target=''

  while (( $# > 0 )); do
    case "$1" in
      -h|--help)
        printf 'usage: digger.sh cdn <host>\n'
        return 0 ;;
      *)
        if [[ -z "$target" ]]; then target="$1"; fi
        shift ;;
    esac
  done

  heading "CDN AND WAF DETECTION"
  hr 60

  if [[ -z "$target" ]]; then
    target=$(prompt "Host")
  fi
  target="${target// /}"
  target="${target,,}"
  target="${target#https://}"
  target="${target#http://}"
  target="${target%%/*}"

  if [[ -z "$target" ]]; then
    err "no target given"
    return 1
  fi
  if ! is_hostname "$target" && ! is_ip "$target"; then
    err "invalid host: ${target}"
    return 1
  fi

  info "Target: ${C_BOLD}${target}${C_RESET}"

  # --- resolution ---------------------------------------------------------
  local ip='' asn='' asn_org='' cnames=''
  ip=$(resolve_host "$target" || true)
  if [[ -n "$ip" ]]; then
    local geo
    geo=$(http_get "https://ipwho.is/${ip}" "$HTTP_TIMEOUT" 1) || geo=''
    if [[ -n "$geo" ]]; then
      asn=$(json_get "$geo" '.connection.asn' || true)
      asn_org=$(json_get "$geo" '.connection.org' || true)
    fi
  fi
  cnames=$(dns_cname_chain "$target" || true)

  printf '\n%sResolution%s\n' "$C_BOLD" "$C_RESET"
  printf '  IP address    : %s\n' "${ip:-unresolved}"
  if [[ -n "$asn" ]]; then
    printf '  ASN           : AS%s%s\n' "$asn" "${asn_org:+ ($asn_org)}"
  else
    printf '  ASN           : %sunknown%s\n' "$C_DIM" "$C_RESET"
  fi
  if [[ -n "$cnames" ]]; then
    printf '  CNAME chain   : %s -> %s\n' "$target" "$cnames"
  else
    printf '  CNAME chain   : %snone%s\n' "$C_DIM" "$C_RESET"
  fi

  # --- HTTP headers -------------------------------------------------------
  local url="https://${target}" headers='' code
  code=$(final_status "$url" 12)
  if [[ ! "$code" =~ ^[1-5] ]]; then
    url="http://${target}"
    code=$(final_status "$url" 12)
  fi
  headers=$(final_headers "$url" 12)

  printf '\n%sHTTP response%s\n' "$C_BOLD" "$C_RESET"
  printf '  URL           : %s\n' "$url"
  printf '  Status        : %s\n' "${code:-unknown}"
  local hname hval
  while IFS= read -r hname; do
    hval=$(header_value "$headers" "$hname")
    [[ -n "$hval" ]] && printf '  %-16s: %s\n' "$hname" "$hval"
  done <<< "server
x-powered-by
via
cf-ray
cf-cache-status
x-amz-cf-id
x-akamai-transformed
x-fastly-request-id
x-azure-ref
x-vercel-id
x-nf-request-id
x-sucuri-id
x-served-by
x-cache
content-type
strict-transport-security"

  # --- certificate issuer -------------------------------------------------
  local issuer=''
  if have openssl; then
    issuer=$(tls_leaf_cert "$target" 443 2>/dev/null \
      | openssl x509 -noout -issuer 2>/dev/null | sed 's/^issuer=//; s/^ *//' || true)
  fi

  # --- detection ----------------------------------------------------------
  # A provider is only reported as detected when a header, CNAME or
  # certificate signature matches. An ASN match on its own is weak evidence.
  local -a cdn_hits=() waf_hits=() cdn_weak=() evidence=()
  local row name hdrs cname_p issuer_p asns h
  local -a hs=() sm=() wm=()

  for row in "${CDN_TABLE[@]}"; do
    IFS='|' read -r name hdrs cname_p issuer_p asns <<< "$row"
    sm=(); wm=()
    IFS=',' read -ra hs <<< "$hdrs"
    for h in "${hs[@]}"; do
      if header_present "$headers" "$h"; then
        sm+=("header ${h}")
      fi
    done
    if [[ -n "$cname_p" ]] && printf '%s' "$cnames" | grep -qi -- "$cname_p"; then
      sm+=("CNAME contains ${cname_p}")
    fi
    if [[ -n "$issuer_p" ]] && printf '%s' "$issuer" | grep -qi -- "$issuer_p"; then
      sm+=("certificate issuer contains ${issuer_p}")
    fi
    if [[ -n "$asns" && -n "$asn" ]] && printf ',%s,' "$asns" | grep -q ",${asn},"; then
      wm+=("ASN AS${asn}")
    fi
    if (( ${#sm[@]} > 0 )); then
      cdn_hits+=("$name")
      for m in "${sm[@]}"; do evidence+=("CDN|${name}|${m}"); done
    elif (( ${#wm[@]} > 0 )); then
      cdn_weak+=("$name")
      for m in "${wm[@]}"; do evidence+=("CDN|${name}|${m}"); done
    fi
  done

  local cookies
  cookies=$(printf '%s' "$headers" | grep -i '^set-cookie:' || true)

  for row in "${WAF_TABLE[@]}"; do
    IFS='|' read -r name hdrs cookie <<< "$row"
    sm=(); wm=()
    IFS=',' read -ra hs <<< "$hdrs"
    for h in "${hs[@]}"; do
      if header_present "$headers" "$h"; then
        sm+=("header ${h}")
      fi
    done
    if [[ -n "$cookie" ]] && printf '%s' "$cookies" | grep -qi -- "$cookie"; then
      sm+=("cookie ${cookie}")
    fi
    if (( ${#sm[@]} > 0 )); then
      waf_hits+=("$name")
      for m in "${sm[@]}"; do evidence+=("WAF|${name}|${m}"); done
    fi
  done

  printf '\n%sDetection%s\n' "$C_BOLD" "$C_RESET"
  if (( ${#cdn_hits[@]} == 0 )); then
    printf '  %s[-]%s no CDN signature matched\n' "$C_DIM" "$C_RESET"
  else
    printf '  %s[+]%s CDN: %s\n' "$C_GREEN" "$C_RESET" "${cdn_hits[*]}"
  fi
  if (( ${#cdn_weak[@]} > 0 )); then
    printf '  %s[!]%s possible CDN (ASN only): %s\n' "$C_YELLOW" "$C_RESET" "${cdn_weak[*]}"
  fi
  if (( ${#waf_hits[@]} == 0 )); then
    printf '  %s[-]%s no WAF signature matched\n' "$C_DIM" "$C_RESET"
  else
    printf '  %s[+]%s WAF: %s\n' "$C_GREEN" "$C_RESET" "${waf_hits[*]}"
  fi

  if (( ${#evidence[@]} > 0 )); then
    printf '\n%sEvidence%s\n' "$C_BOLD" "$C_RESET"
    local e kind who what
    for e in "${evidence[@]}"; do
      IFS='|' read -r kind who what <<< "$e"
      printf '  %-4s %-20s %s\n' "$kind" "$who" "$what"
    done
  fi

  # --- host header behaviour ---------------------------------------------
  printf '\n%sHost header handling%s\n' "$C_BOLD" "$C_RESET"
  local hcode
  hcode=$(curl -s -o /dev/null -k -L --max-time 10 -H "User-Agent: $USER_AGENT" \
    -H "Host: definitely-not-a-real-host-zzz.invalid" -w '%{http_code}' "$url" 2>/dev/null || true)
  if [[ "$hcode" == "$code" ]]; then
    printf '  %s[!]%s the server answers the same for an unknown Host header\n' "$C_YELLOW" "$C_RESET"
  else
    printf '  %s[+]%s the server reacts to the Host header (%s -> %s)\n' "$C_GREEN" "$C_RESET" "$code" "$hcode"
  fi
  return 0
}

# --- Module 13: Threat Intelligence ----------------------------------------
DNSBL_ZONES=(
  "zen.spamhaus.org"
  "bl.spamcop.net"
  "b.barracudacentral.org"
  "psbl.surriel.com"
  "dnsbl.sorbs.net"
  "dnsbl-1.uceprotect.net"
)

# Look a host up in a DNS blacklist.
#   0 = listed (the return code is printed)
#   1 = not listed
#   2 = skipped (IPv6 or no resolver)
dnsbl_lookup() {
  local ip="$1" zone="$2" result=''
  if ! is_ipv4 "$ip"; then
    return 2
  fi
  local rev
  rev=$(printf '%s' "$ip" | awk -F. '{print $4"."$3"."$2"."$1}')
  result=$(dns_query "${rev}.${zone}" A 2>/dev/null | head -n1 || true)
  [[ -z "$result" ]] && return 1
  printf '%s' "$result"
  return 0
}

# Turn a DNSBL return code into something readable.
dnsbl_meaning() {
  local code="$1"
  case "$code" in
    127.255.255.252) printf 'query refused, public resolver blocked' ;;
    127.255.255.254) printf 'query refused, resolver is blocked' ;;
    127.255.255.255) printf 'query refused' ;;
    127.0.0.2|127.0.0.2*) printf 'listed' ;;
    127.0.0.*)        printf 'listed (code %s)' "${code##*.}" ;;
    *)                printf 'listed (code %s)' "$code" ;;
  esac
}

mod_intel() {
  local target=''

  while (( $# > 0 )); do
    case "$1" in
      -h|--help)
        printf 'usage: digger.sh intel <ip|domain|url>\n'
        return 0 ;;
      *)
        if [[ -z "$target" ]]; then target="$1"; fi
        shift ;;
    esac
  done

  heading "THREAT INTELLIGENCE"
  hr 60

  if [[ -z "$target" ]]; then
    target=$(prompt "IP address, domain or URL")
  fi
  target="${target// /}"
  if [[ -z "$target" ]]; then
    err "no target given"
    return 1
  fi

  # A URL is reduced to its host.
  if [[ "$target" == *"://"* ]]; then
    target="${target#*://}"
    target="${target%%/*}"
  fi
  target="${target,,}"

  local is_domain=0 ip=''
  if is_ip "$target"; then
    ip="$target"
  elif is_hostname "$target"; then
    is_domain=1
    ip=$(resolve_host "$target" || true)
  else
    err "invalid target: ${target}"
    return 1
  fi

  info "Target: ${C_BOLD}${target}${C_RESET}"
  if (( is_domain )) && [[ -n "$ip" ]]; then
    printf '  Resolves to: %s\n' "$ip"
  fi

  local -a findings=()
  local listed=0 refused=0 checked=0

  # --- DNS blacklists -----------------------------------------------------
  printf '\n%sDNS blacklists%s\n' "$C_BOLD" "$C_RESET"
  if [[ -z "$ip" ]]; then
    printf '  %s[!]%s the host does not resolve, skipping DNS blacklists\n' "$C_YELLOW" "$C_RESET"
  else
    local zone code rc meaning
    for zone in "${DNSBL_ZONES[@]}"; do
      rc=0
      code=$(dnsbl_lookup "$ip" "$zone") || rc=$?
      case "$rc" in
        0)
          checked=$((checked + 1))
          meaning=$(dnsbl_meaning "$code")
          if [[ "$meaning" == listed* ]]; then
            printf '  %s[!]%s %-30s %s\n' "$C_RED" "$C_RESET" "$zone" "$meaning"
            findings+=("listed on ${zone} (${code})")
            listed=$((listed + 1))
          else
            printf '  %s[-]%s %-30s %s\n' "$C_DIM" "$C_RESET" "$zone" "$meaning"
            refused=$((refused + 1))
          fi
          ;;
        1)
          checked=$((checked + 1))
          printf '  %s[+]%s %-30s not listed\n' "$C_GREEN" "$C_RESET" "$zone"
          ;;
        *)
          printf '  %s[-]%s %-30s skipped\n' "$C_DIM" "$C_RESET" "$zone"
          ;;
      esac
    done
  fi

  # --- IP blacklists ------------------------------------------------------
  printf '\n%sIP blacklists%s\n' "$C_BOLD" "$C_RESET"
  if [[ -z "$ip" ]]; then
    printf '  %s[!]%s no address to check\n' "$C_YELLOW" "$C_RESET"
  else
    local body

    body=$(http_get "https://api.blocklist.de/api.php?ip=${ip}" "$HTTP_TIMEOUT" 1) || body=''
    checked=$((checked + 1))
    if [[ -n "$body" ]]; then
      # the endpoint answers with a small HTML fragment such as
      # "attacks: 3<br />reports: 12<br />"
      local attacks='0' reports='0'
      attacks=$(printf '%s' "$body" | grep -oiE 'attacks:[^<0-9]*[0-9]+' | grep -oE '[0-9]+$' || true)
      reports=$(printf '%s' "$body" | grep -oiE 'reports:[^<0-9]*[0-9]+' | grep -oE '[0-9]+$' || true)
      [[ "$attacks" =~ ^[0-9]+$ ]] || attacks=0
      [[ "$reports" =~ ^[0-9]+$ ]] || reports=0
      if (( attacks > 0 || reports > 0 )); then
        printf '  %s[!]%s %-30s %s\n' "$C_RED" "$C_RESET" "blocklist.de" "listed (${attacks} attacks, ${reports} reports)"
        findings+=("listed on blocklist.de (${attacks} attacks, ${reports} reports)")
        listed=$((listed + 1))
      elif printf '%s' "$body" | grep -qE '127\.0\.0\.[0-9]+'; then
        printf '  %s[!]%s %-30s %s\n' "$C_RED" "$C_RESET" "blocklist.de" "listed"
        findings+=("listed on blocklist.de")
        listed=$((listed + 1))
      elif printf '%s' "$body" | grep -qi 'no address'; then
        printf '  %s[+]%s %-30s not listed\n' "$C_GREEN" "$C_RESET" "blocklist.de"
      else
        printf '  %s[+]%s %-30s not listed\n' "$C_GREEN" "$C_RESET" "blocklist.de"
      fi
    else
      printf '  %s[-]%s %-30s source unavailable\n' "$C_DIM" "$C_RESET" "blocklist.de"
    fi

    body=$(http_get "https://cinsscore.com/list/ci-badguys.txt" 25 1) || body=''
    checked=$((checked + 1))
    if [[ -n "$body" ]]; then
      if printf '%s\n' "$body" | grep -qE "(^|[^0-9.])${ip}([^0-9.]|$)"; then
        printf '  %s[!]%s %-30s %s\n' "$C_RED" "$C_RESET" "cinsscore.com" "listed"
        findings+=("listed on cinsscore.com")
        listed=$((listed + 1))
      else
        printf '  %s[+]%s %-30s not listed\n' "$C_GREEN" "$C_RESET" "cinsscore.com"
      fi
    else
      printf '  %s[-]%s %-30s source unavailable\n' "$C_DIM" "$C_RESET" "cinsscore.com"
    fi

    body=$(http_get "https://check.torproject.org/torbulkexitlist" 25 1) || body=''
    checked=$((checked + 1))
    if [[ -n "$body" ]]; then
      if printf '%s\n' "$body" | grep -qE "(^|[^0-9.])${ip}([^0-9.]|$)"; then
        printf '  %s[!]%s %-30s %s\n' "$C_RED" "$C_RESET" "tor exit nodes" "listed"
        findings+=("listed as a Tor exit node")
        listed=$((listed + 1))
      else
        printf '  %s[+]%s %-30s not listed\n' "$C_GREEN" "$C_RESET" "tor exit nodes"
      fi
    else
      printf '  %s[-]%s %-30s source unavailable\n' "$C_DIM" "$C_RESET" "tor exit nodes"
    fi
  fi

  # --- phishing feeds -----------------------------------------------------
  printf '\n%sPhishing feeds%s\n' "$C_BOLD" "$C_RESET"
  if (( is_domain == 0 )); then
    printf '  %s[-]%s domain feeds only apply to a hostname\n' "$C_DIM" "$C_RESET"
  else
    local feed
    feed=$(http_get "https://openphish.com/feed.txt" 25 1) || feed=''
    checked=$((checked + 1))
    if [[ -n "$feed" ]]; then
      if printf '%s\n' "$feed" | grep -qiF "$target"; then
        printf '  %s[!]%s %-30s %s\n' "$C_RED" "$C_RESET" "openphish.com" "listed"
        findings+=("listed on openphish.com")
        listed=$((listed + 1))
      else
        printf '  %s[+]%s %-30s not listed\n' "$C_GREEN" "$C_RESET" "openphish.com"
      fi
    else
      printf '  %s[-]%s %-30s source unavailable\n' "$C_DIM" "$C_RESET" "openphish.com"
    fi
  fi

  # --- summary ------------------------------------------------------------
  printf '\n%sSummary%s\n' "$C_BOLD" "$C_RESET"
  if (( listed == 0 )); then
    printf '  %s[+]%s no listings found across %s checks\n' "$C_GREEN" "$C_RESET" "$checked"
  else
    printf '  %s[!]%s %s listing(s) found:\n' "$C_RED" "$C_RESET" "$listed"
    local f
    for f in "${findings[@]}"; do
      printf '      - %s\n' "$f"
    done
  fi
  if (( refused > 0 )); then
    printf '  %s[!]%s %s blacklist(s) refused the query, treat those as unknown\n' "$C_YELLOW" "$C_RESET" "$refused"
  fi
  return 0
}

read -r -d '' PY_JSON_MAP <<'PYEOF' || true
import json, sys
try:
    sys.stdout.reconfigure(newline='\n')
except Exception:
    pass
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(1)
field = sys.argv[1]
items = data if isinstance(data, list) else [data]
for item in items:
    if not isinstance(item, dict) or field not in item:
        continue
    value = item[field]
    if isinstance(value, list):
        for v in value:
            if isinstance(v, (dict, list)):
                print(json.dumps(v))
            else:
                for line in str(v).split('\n'):
                    if line:
                        print(line)
    elif isinstance(value, (dict, list)):
        print(json.dumps(value))
    else:
        for line in str(value).split('\n'):
            if line:
                print(line)
PYEOF

# Print one field for every object of a JSON array, one value per line.
json_map() {
  local json="$1" field="$2"
  [[ -z "$json" ]] && return 1
  if have jq; then
    printf '%s' "$json" | jq -r --arg f "$field" '.[]? | .[$f]? | if type == "array" then .[] else . end' 2>/dev/null
    return $?
  fi
  printf '%s' "$json" | "$PY" -c "$PY_JSON_MAP" "$field" 2>/dev/null
}

# Normalise a candidate name and make sure it belongs to the target domain.
sub_clean_name() {
  local n="$1" domain="$2"
  n="${n,,}"
  n="${n//$'\r'/}"
  n="${n//$'\n'/}"
  n="${n%.}"
  n="${n#\*.}"
  n="${n#\*}"
  [[ -z "$n" ]] && return 1
  [[ "$n" == "$domain" ]] && return 1
  [[ "$n" == *".${domain}" ]] || return 1
  is_hostname "$n" || return 1
  # Sets a variable instead of printing: this runs for every candidate and a
  # fork per call would dominate the runtime.
  SUB_CLEAN_RESULT="$n"
  return 0
}

# --- Module 8: Subdomain Finder --------------------------------------------
# Core labels the pattern generator works on.
SUB_CORE_LABELS=(
  www web api dev test stage staging qa uat prod demo sandbox preview
  mail smtp ftp ns ns1 ns2 mx cpanel whm admin administrator root login
  dashboard portal intranet extranet internal vpn remote ssh git gitlab
  jenkins ci cd build deploy release monitor status
  help support docs doc wiki blog shop store payment invoice
  auth sso oauth identity gateway proxy db database redis elastic
  search static assets cdn media img images files upload downloads mobile
  app apps api1 api2 api3 server host node worker cloud
)
SUB_ENV_WORDS=(dev test staging qa prod demo)

# Candidate names produced by the pattern generator: label-env for every core
# label plus env-label for the labels that usually carry an environment.
sub_gen_patterns() {
  local domain="$1" label env
  for label in "${SUB_CORE_LABELS[@]}"; do
    for env in "${SUB_ENV_WORDS[@]}"; do
      [[ "$env" == "$label" ]] && continue
      printf '%s-%s.%s\n' "$label" "$env" "$domain"
    done
  done
  for label in www api app admin auth mail db db1 git vpn shop cdn ns; do
    for env in "${SUB_ENV_WORDS[@]}"; do
      printf '%s-%s.%s\n' "$env" "$label" "$domain"
    done
  done
}

# Names from the certificate transparency logs. Both logs are queried at the
# same time, they are slow and independent of each other.
sub_collect_ct() {
  local domain="$1"

  (
    local body
    body=$(http_get "https://crt.sh/?q=%25.${domain}&output=json&exclude=expired" 20 1) || body=''
    if [[ -n "$body" && "$body" == \[* ]]; then
      json_map "$body" 'name_value' 2>/dev/null || true
      json_map "$body" 'common_name' 2>/dev/null || true
    fi
  ) &

  (
    local body
    body=$(http_get "https://api.certspotter.com/v1/issuances?domain=${domain}&include_subdomains=true&expand=dns_names" 20 1) || body=''
    if [[ -n "$body" && "$body" == \[* ]]; then
      json_map "$body" 'dns_names' 2>/dev/null || true
    fi
  ) &

  wait
}

# Names from subdomain.center, a keyless passive aggregator.
sub_collect_agg() {
  local domain="$1" body
  body=$(http_get "https://api.subdomain.center/?domain=${domain}" 25 1) || body=''
  if [[ -n "$body" && "$body" == \[* ]]; then
    json_get "$body" '.[]' 2>/dev/null || true
  fi
}

# Names and addresses from the passive DNS sources.
sub_collect_pdns() {
  local domain="$1"

  (
    local body
    body=$(http_get "https://api.mnemonic.no/pdns/v3/${domain}" 20 1) || body=''
    if [[ -n "$body" && "$body" == \{* ]] && [[ -n "$PY" ]]; then
      printf '%s' "$body" | "$PY" -c "
import json, sys
try:
    sys.stdout.reconfigure(newline='\n')
except Exception:
    pass
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for row in (data.get('data') or []):
    q = (row.get('query') or '').lower()
    a = (row.get('answer') or '').lower()
    if q and a:
        print(q + '\t' + a)
" 2>/dev/null || true
    fi
  ) &

  (
    local body
    body=$(http_get "https://api.hackertarget.com/hostsearch/?q=${domain}" 12 1) || body=''
    if [[ -n "$body" ]] && printf '%s' "$body" | grep -qiE '^[a-z0-9.-]+,[0-9a-f.:]+$'; then
      printf '%s\n' "$body" | tr '[:upper:]' '[:lower:]' | grep -E '^[a-z0-9._-]+,[0-9a-f.:]+$' || true
    fi
  ) &

  wait
}

# Resolve a batch of names with dig in one go.
sub_resolve_dig_chunk() {
  local -a args=()
  local n
  for n in "$@"; do
    args+=("$n" A)
  done
  (( ${#args[@]} == 0 )) && return 0

  local answers
  answers=$(dig +noall +answer +time=4 +tries=1 "${args[@]}" 2>/dev/null | awk '
    {
      owner = tolower($1); sub(/\.$/, "", owner)
      type  = tolower($4)
      if (type == "a")          printf "A\t%s\t%s\n", owner, $5
      else if (type == "aaaa")  printf "6\t%s\t%s\n", owner, $5
      else if (type == "cname") { data = tolower($5); sub(/\.$/, "", data); printf "C\t%s\t%s\n", owner, data }
    }' | sort -u) || answers=''

  # CNAME chains: build owner -> target and owner -> address maps, then walk
  # each queried name until an address is found.
  local -A a_map=() c_map=()
  local t owner val
  while IFS=$'\t' read -r t owner val; do
    [[ -z "$t" ]] && continue
    case "$t" in
      A|6) a_map["$owner"]="$val" ;;
      C)   c_map["$owner"]="$val" ;;
    esac
  done <<< "$answers"

  local cur hops
  for n in "$@"; do
    n="${n%.}"
    cur="$n"
    hops=0
    while (( hops < 8 )); do
      if [[ -n "${a_map[$cur]:-}" ]]; then
        printf '%s\t%s\n' "$n" "${a_map[$cur]}"
        break
      fi
      cur="${c_map[$cur]:-}"
      [[ -z "$cur" ]] && break
      hops=$(( hops + 1 ))
    done
  done
}

# Pick the first address out of a DNS over HTTPS answer.
sub_doh_pick_ip() {
  local json="$1" line
  [[ -z "$json" ]] && return 1
  while IFS= read -r line; do
    if is_ipv4 "$line" || is_ipv6 "$line"; then
      printf '%s' "$line"
      return 0
    fi
  done < <(json_get "$json" '.Answer[].data' 2>/dev/null || true)
  return 1
}

# Resolve a single name over DNS over HTTPS.
sub_resolve_doh_one() {
  local name="$1" json ip
  json=$(http_get "https://dns.google/resolve?name=${name}&type=A" 8 1) || json=''
  ip=$(sub_doh_pick_ip "$json" || true)
  [[ -z "$ip" ]] && return 0
  printf '%s\t%s\n' "$name" "$ip"
}

# Resolve every candidate name. Reads names on stdin, prints "name<TAB>ip".
sub_resolve_all() {
  local threads="${1:-10}"
  local -a names=()
  local n
  while IFS= read -r n; do
    [[ -z "$n" ]] && continue
    names+=("$n")
  done
  (( ${#names[@]} == 0 )) && return 0

  if have dig; then
    # dig answers many questions in one run, so the work is split into chunks
    # that are queried at the same time.
    local -a chunk=()
    local -a pids=()
    for n in "${names[@]}"; do
      chunk+=("$n")
      if (( ${#chunk[@]} >= 120 )); then
        sub_resolve_dig_chunk "${chunk[@]}" &
        pids+=($!)
        chunk=()
        if (( ${#pids[@]} >= threads )); then
          wait "${pids[0]}" 2>/dev/null || true
          pids=("${pids[@]:1}")
        fi
      fi
    done
    if (( ${#chunk[@]} > 0 )); then
      sub_resolve_dig_chunk "${chunk[@]}" &
      pids+=($!)
    fi
    wait 2>/dev/null || true
    return 0
  fi

  # No dig, fall back to DNS over HTTPS. One request per name, so keep the
  # number of parallel workers small and the request count sane.
  local -a pids=()
  for n in "${names[@]}"; do
    sub_resolve_doh_one "$n" &
    pids+=($!)
    if (( ${#pids[@]} >= threads )); then
      wait "${pids[0]}" 2>/dev/null || true
      pids=("${pids[@]:1}")
    fi
  done
  wait 2>/dev/null || true
}

# Does the domain answer for a name that cannot exist?
sub_check_wildcard() {
  local domain="$1" probe out ip line
  probe="digger-wildcard-$$-${RANDOM}-${RANDOM}.${domain}"
  out=$(resolve_host "$probe" || true)
  [[ -z "$out" ]] && return 1
  ip=''
  while IFS= read -r line; do
    if is_ipv4 "$line" || is_ipv6 "$line"; then
      ip="$line"
      break
    fi
  done <<< "$out"
  [[ -z "$ip" ]] && ip="$out"
  printf '%s' "$ip"
}

mod_subdomains() {
  local target='' wordlist='' use_ct=1 use_pdns=1 use_wl=1 use_pattern=1 threads=10 limit=0 resolve=1

  while (( $# > 0 )); do
    case "$1" in
      --wordlist)     wordlist="${2:-}"; shift 2 || shift ;;
      --no-ct)        use_ct=0; shift ;;
      --no-pdns)      use_pdns=0; shift ;;
      --no-wordlist)  use_wl=0; shift ;;
      --no-pattern)   use_pattern=0; shift ;;
      --no-resolve)   resolve=0; shift ;;
      --threads)      threads="${2:-10}"; shift 2 || shift ;;
      --limit)        limit="${2:-0}"; shift 2 || shift ;;
      -h|--help)
        printf 'usage: digger.sh subdomains <domain> [--wordlist FILE] [--no-ct] [--no-pdns] [--no-wordlist] [--no-pattern] [--no-resolve] [--threads N] [--limit N]\n'
        return 0 ;;
      *)
        if [[ -z "$target" ]]; then target="$1"; fi
        shift ;;
    esac
  done

  heading "SUBDOMAIN FINDER"
  hr 60

  if [[ -z "$target" ]]; then
    target=$(prompt "Domain")
  fi
  target="${target// /}"
  target="${target,,}"
  target="${target#https://}"
  target="${target#http://}"
  target="${target%%/*}"
  target="${target%%:*}"

  if [[ -z "$target" ]]; then
    err "no target given"
    return 1
  fi
  if ! is_hostname "$target"; then
    err "invalid domain: ${target}"
    return 1
  fi

  info "Target: ${C_BOLD}${target}${C_RESET}"

  # --- sources -----------------------------------------------------------
  if [[ -z "$wordlist" ]]; then
    wordlist=$(wordlist_file "subdomains.txt" || true)
  fi

  printf '\n%sSources%s\n' "$C_BOLD" "$C_RESET"
  (( use_ct ))   && printf '  certificate transparency : crt.sh, certspotter\n'
  (( use_pdns )) && printf '  passive DNS               : mnemonic.no, hackertarget\n'
  (( use_ct ))   && printf '  passive aggregator        : subdomain.center\n'
  if (( use_wl )); then
    if [[ -n "$wordlist" && -f "$wordlist" ]]; then
      printf '  wordlist                  : %s (%s labels)\n' "$wordlist" "$(grep -cvE '^[[:space:]]*(#|$)' "$wordlist" || true)"
    else
      printf '  wordlist                  : %snot found%s\n' "$C_DIM" "$C_RESET"
      use_wl=0
    fi
  fi
  (( use_pattern )) && printf '  pattern generator         : %s core labels x %s environments\n' "${#SUB_CORE_LABELS[@]}" "${#SUB_ENV_WORDS[@]}"
  printf '  wildcard filter           : enabled\n'

  # --- passive collection -------------------------------------------------
  local -a ct_names=() pdns_names=() wl_names=() pat_names=()
  local raw='' n

  if (( use_ct || use_pdns )); then
    printf '  %s[+]%s querying passive sources in parallel...\n' "$C_DIM" "$C_RESET"
    raw=$(
      { (( use_ct )) && sub_collect_ct "$target"; } &
      { (( use_pdns )) && sub_collect_pdns "$target"; } &
      { (( use_ct )) && sub_collect_agg "$target"; } &
      wait
    )
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      if [[ "$line" == *$'\t'* ]]; then
        pdns_names+=("$line")
      else
        ct_names+=("$line")
      fi
    done <<< "$raw"
    printf '  %s[+]%s passive sources: %s names, %s with an address\n' \
      "$C_GREEN" "$C_RESET" "${#ct_names[@]}" "${#pdns_names[@]}"
    if (( ${#ct_names[@]} == 0 && ${#pdns_names[@]} == 0 )); then
      printf '  %s[!]%s every passive source came back empty (they rate limit hard)\n' "$C_YELLOW" "$C_RESET"
      printf '      %stry again in a minute, or lean on the wordlist%s\n' "$C_DIM" "$C_RESET"
    fi
  fi

  if (( use_wl )) && [[ -n "$wordlist" && -f "$wordlist" ]]; then
    printf '  %s[+]%s loading the wordlist...\n' "$C_DIM" "$C_RESET"
    while IFS= read -r label; do
      label="${label%$'\r'}"
      [[ -z "$label" ]] && continue
      [[ "$label" == \#* ]] && continue
      [[ "$label" == *.* ]] && continue
      wl_names+=("${label}.${target}")
    done < "$wordlist"
    printf '  %s[+]%s wordlist: %s candidates\n' "$C_GREEN" "$C_RESET" "${#wl_names[@]}"
  fi

  if (( use_pattern )); then
    printf '  %s[+]%s generating patterns...\n' "$C_DIM" "$C_RESET"
    while IFS= read -r n; do
      [[ -z "$n" ]] && continue
      pat_names+=("$n")
    done < <(sub_gen_patterns "$target")
    printf '  %s[+]%s patterns: %s candidates\n' "$C_GREEN" "$C_RESET" "${#pat_names[@]}"
  fi

  # --- wildcard ----------------------------------------------------------
  local wildcard=''
  wildcard=$(sub_check_wildcard "$target" || true)
  if [[ -n "$wildcard" ]]; then
    printf '  %s[!]%s wildcard DNS detected, every name resolves to %s\n' "$C_YELLOW" "$C_RESET" "$wildcard"
    printf '      %sresults from the wordlist and the generator are unreliable%s\n' "$C_DIM" "$C_RESET"
  else
    printf '  %s[+]%s no wildcard DNS record\n' "$C_GREEN" "$C_RESET"
  fi

  # --- merge candidates ---------------------------------------------------
  local -A seen=() from_ct=() from_pdns=() from_wl=() from_pat=()
  local cn

  for n in ${ct_names[@]+"${ct_names[@]}"}; do
    sub_clean_name "$n" "$target" || continue
    cn="$SUB_CLEAN_RESULT"
    from_ct["$cn"]=1
  done
  for n in ${pdns_names[@]+"${pdns_names[@]}"}; do
    n="${n%%$'\t'*}"
    sub_clean_name "$n" "$target" || continue
    cn="$SUB_CLEAN_RESULT"
    from_pdns["$cn"]=1
  done
  for n in ${wl_names[@]+"${wl_names[@]}"}; do
    sub_clean_name "$n" "$target" || continue
    cn="$SUB_CLEAN_RESULT"
    from_wl["$cn"]=1
  done
  for n in ${pat_names[@]+"${pat_names[@]}"}; do
    sub_clean_name "$n" "$target" || continue
    cn="$SUB_CLEAN_RESULT"
    from_pat["$cn"]=1
  done

  for n in "${!from_ct[@]}"; do seen["$n"]=1; done
  for n in "${!from_pdns[@]}"; do seen["$n"]=1; done
  for n in "${!from_wl[@]}"; do seen["$n"]=1; done
  for n in "${!from_pat[@]}"; do seen["$n"]=1; done

  # Display order is alphabetical.
  local -a candidates=()
  while IFS= read -r n; do
    [[ -z "$n" ]] && continue
    candidates+=("$n")
  done < <(printf '%s\n' "${!seen[@]}" | sort)

  # Resolution order matters: names seen in a passive source are always
  # checked, the brute force part follows the wordlist order so a truncated
  # run still looks at the most likely names first.
  local -a passive=() brute=()
  for n in ${candidates[@]+"${candidates[@]}"}; do
    if [[ -n "${from_ct[$n]:-}" || -n "${from_pdns[$n]:-}" ]]; then
      passive+=("$n")
    fi
  done
  for n in ${wl_names[@]+"${wl_names[@]}"}; do
    sub_clean_name "$n" "$target" || continue
    n="$SUB_CLEAN_RESULT"
    [[ -n "${from_ct[$n]:-}" || -n "${from_pdns[$n]:-}" ]] && continue
    brute+=("$n")
  done
  for n in ${pat_names[@]+"${pat_names[@]}"}; do
    sub_clean_name "$n" "$target" || continue
    n="$SUB_CLEAN_RESULT"
    [[ -n "${from_ct[$n]:-}" || -n "${from_pdns[$n]:-}" ]] && continue
    brute+=("$n")
  done

  printf '\n%sCandidates%s\n' "$C_BOLD" "$C_RESET"
  printf '  %s unique names, %s from passive sources\n' "${#candidates[@]}" "${#passive[@]}"

  # --- resolution ---------------------------------------------------------
  local -A resolved=()
  if (( resolve )); then
    local resolver='DNS over HTTPS (dns.google)'
    local budget="$limit"
    if have dig; then
      resolver='dig (system resolver)'
      (( budget > 0 )) || budget=1500
    else
      (( budget > 0 )) || budget=150
    fi

    local -a todo=("${passive[@]+"${passive[@]}"}")
    if (( ${#brute[@]} > budget )); then
      todo+=("${brute[@]:0:budget}")
      printf '  %s[!]%s brute force limited to %s names, raise it with --limit\n' "$C_YELLOW" "$C_RESET" "$budget"
    else
      todo+=("${brute[@]+"${brute[@]}"}")
    fi

    printf '  %s[+]%s resolving %s names with %s...\n' "$C_DIM" "$C_RESET" "${#todo[@]}" "$resolver"
    raw=$(printf '%s\n' ${todo[@]+"${todo[@]}"} | sub_resolve_all "$threads")
    while IFS=$'\t' read -r n ip; do
      [[ -z "$n" ]] && continue
      resolved["$n"]="$ip"
    done <<< "$raw"
    printf '  %s[+]%s %s names resolve\n' "$C_GREEN" "$C_RESET" "${#resolved[@]}"
  fi

  # --- cross check with a second resolver ---------------------------------
  local -A confirmed=()
  if (( resolve )) && (( ${#resolved[@]} > 0 )); then
    local -a sample=()
    for n in "${!resolved[@]}"; do
      sample+=("$n")
    done
    if (( ${#sample[@]} > 25 )); then
      sample=("${sample[@]:0:25}")
    fi
    local cname cip cjson
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      cname="${line%%$'\t'*}"
      cip="${line#*$'\t'}"
      confirmed["$cname"]="$cip"
    done < <(printf '%s\n' ${sample[@]+"${sample[@]}"} | while IFS= read -r x; do
      cjson=$(http_get "https://cloudflare-dns.com/dns-query?name=${x}&type=A" 8 1) || cjson=''
      cip=$(sub_doh_pick_ip "$cjson" || true)
      [[ -z "$cip" ]] && continue
      printf '%s\t%s\n' "$x" "$cip"
    done)
  fi

  # --- classification -----------------------------------------------------
  local -a high=() medium=() low=()
  local source ip conf
  for n in ${candidates[@]+"${candidates[@]}"}; do
    ip="${resolved[$n]:-}"
    source=''
    [[ -n "${from_ct[$n]:-}" ]] && source="${source}ct "
    [[ -n "${from_pdns[$n]:-}" ]] && source="${source}pdns "
    [[ -n "${from_wl[$n]:-}" ]] && source="${source}wordlist "
    [[ -n "${from_pat[$n]:-}" ]] && source="${source}pattern "
    source="${source% }"

    conf=''
    [[ -n "${confirmed[$n]:-}" ]] && conf=' (2 resolvers)'

    if [[ -n "$ip" ]]; then
      if [[ -n "${from_ct[$n]:-}" || -n "${from_pdns[$n]:-}" ]]; then
        high+=("${ip}|${n}|${source}${conf}")
      else
        medium+=("${ip}|${n}|${source}${conf}")
      fi
    elif [[ -n "${from_ct[$n]:-}" || -n "${from_pdns[$n]:-}" ]]; then
      low+=("-|${n}|${source}")
    fi
  done

  printf '\n%sResults%s\n' "$C_BOLD" "$C_RESET"
  printf '  %s high, %s medium, %s low confidence\n' "${#high[@]}" "${#medium[@]}" "${#low[@]}"

  local group title colour entry c s t p
  local -a entries=()
  for group in high medium low; do
    entries=()
    case "$group" in
      high)   title="HIGH CONFIDENCE";   colour="$C_GREEN";  entries=(${high[@]+"${high[@]}"}) ;;
      medium) title="MEDIUM CONFIDENCE"; colour="$C_YELLOW"; entries=(${medium[@]+"${medium[@]}"}) ;;
      low)    title="LOW CONFIDENCE";    colour="$C_DIM";    entries=(${low[@]+"${low[@]}"}) ;;
    esac
    (( ${#entries[@]} == 0 )) && continue
    printf '\n%s%s%s (%s)\n' "$colour" "$title" "$C_RESET" "${#entries[@]}"
    for entry in "${entries[@]}"; do
      IFS='|' read -r c s t p <<< "$entry"
      printf '  %s%-15s%s %-44s %s\n' "$colour" "$c" "$C_RESET" "$s" "$t"
    done
  done

  # --- summary ------------------------------------------------------------
  local srcs=''
  (( use_ct )) && srcs="${srcs}crt.sh, certspotter, subdomain.center, "
  (( use_pdns )) && srcs="${srcs}mnemonic.no, hackertarget, "
  srcs="${srcs%, }"

  printf '\n%sSummary%s\n' "$C_BOLD" "$C_RESET"
  printf '  Sources     : %s\n' "$srcs"
  if have dig; then
    printf '  Resolver    : dig (system resolver)\n'
  else
    printf '  Resolver    : DNS over HTTPS (dns.google)\n'
  fi
  if [[ -n "$wildcard" ]]; then
    printf '  Wildcard    : %s (every name resolves)\n' "$wildcard"
  else
    printf '  Wildcard    : none\n'
  fi
  printf '  High        : %s\n' "${#high[@]}"
  printf '  Medium      : %s\n' "${#medium[@]}"
  printf '  Low         : %s\n' "${#low[@]}"
  return 0
}

# --- Module 5: Host Finder -------------------------------------------------
# Wrap an address so it can sit inside a URL or a --resolve argument.
host_addr_literal() {
  if is_ipv6 "$1"; then printf '[%s]' "$1"; else printf '%s' "$1"; fi
}

# Reverse DNS: dig, then getent, then DNS over HTTPS for IPv4.
host_ptr() {
  local ip="$1" out='' name json
  if have dig; then
    out=$(dig +short +time=4 +tries=1 -x "$ip" 2>/dev/null | head -n1 || true)
  fi
  if [[ -z "$out" ]] && have getent; then
    out=$(getent hosts "$ip" 2>/dev/null | awk '{print $2; exit}' || true)
  fi
  if [[ -z "$out" ]] && is_ipv4 "$ip"; then
    name=$(printf '%s' "$ip" | awk -F. '{print $4"."$3"."$2"."$1".in-addr.arpa"}')
    json=$(http_get "https://dns.google/resolve?name=${name}&type=PTR" "$HTTP_TIMEOUT" 1) || json=''
    if [[ -n "$json" ]]; then
      out=$(json_get "$json" '.Answer[].data' 2>/dev/null | head -n1 || true)
    fi
  fi
  out="${out%.}"
  [[ -n "$out" ]] || return 1
  printf '%s' "$out"
}

# Names that have historically resolved to an address. Passive sources only,
# queried in parallel, tagged so the caller can count them per source.
host_reverse_passive() {
  local ip="$1"
  (
    local body
    body=$(http_get "https://api.mnemonic.no/pdns/v3/${ip}?limit=100" 20 1) || body=''
    if [[ -n "$body" && "$body" == \{* ]]; then
      json_get "$body" '.data[].query' 2>/dev/null | awk '{print "m\t"$0}' || true
    fi
  ) &
  (
    local body
    body=$(http_get "https://api.hackertarget.com/reverseiplookup/?q=${ip}" 15 1) || body=''
    if [[ -n "$body" && "$body" != *'API count exceeded'* && \
          "$body" != *'error'* && "$body" != *'<'* ]]; then
      printf '%s\n' "$body" | tr -d '\r' \
        | grep -E '^[A-Za-z0-9_.-]+$' | awk '{print "h\t"$0}' || true
    fi
  ) &
  wait
}

# Ask an address for one hostname and record how it answers.
host_probe_vhost() {
  local vhost="$1" ip="$2" timeout="$3"
  local lit out code='' size='' scheme='https'
  lit=$(host_addr_literal "$ip")
  out=$(curl -sS -k --max-time "$timeout" -o /dev/null \
    -w '%{http_code} %{size_download}' \
    --resolve "${vhost}:443:${lit}" "https://${vhost}/" 2>/dev/null || true)
  code="${out%% *}"; size="${out##* }"
  if [[ -z "$out" || "$code" == '000' ]]; then
    out=$(curl -sS --max-time "$timeout" -o /dev/null \
      -w '%{http_code} %{size_download}' \
      -H "Host: ${vhost}" "http://${lit}/" 2>/dev/null || true)
    code="${out%% *}"; size="${out##* }"; scheme='http'
  fi
  [[ "$code" =~ ^[0-9]+$ ]] || code='000'
  [[ "$size" =~ ^[0-9]+$ ]] || size='0'
  printf '%s\t%s\t%s\t%s\n' "$vhost" "$code" "$size" "$scheme"
}

# Probe hostnames read from stdin, keeping at most <conc> requests in flight.
host_probe_all() {
  local ip="$1" conc="$2" timeout="$3"
  local -a pids=()
  local vhost
  while IFS= read -r vhost || [[ -n "$vhost" ]]; do
    [[ -z "$vhost" ]] && continue
    host_probe_vhost "$vhost" "$ip" "$timeout" &
    pids+=($!)
    if (( ${#pids[@]} >= conc )); then
      wait "${pids[0]}" 2>/dev/null || true
      pids=("${pids[@]:1}")
    fi
  done
  wait 2>/dev/null || true
}

mod_hosts() {
  local target='' wordlist='' conc=10 timeout=8 probe=0 limit=100

  while (( $# > 0 )); do
    case "$1" in
      --vhosts)      probe=1; shift ;;
      --no-vhosts)   probe=0; shift ;;
      --wordlist)    wordlist="${2:-}"; shift 2 || shift ;;
      --concurrency) conc="${2:-10}"; shift 2 || shift ;;
      --timeout)     timeout="${2:-8}"; shift 2 || shift ;;
      --limit)       limit="${2:-100}"; shift 2 || shift ;;
      -y|--yes)      ASSUME_YES=1; shift ;;
      -h|--help)
        printf 'usage: digger.sh hosts <domain|ip> [--vhosts] [--wordlist FILE] [--concurrency N] [--timeout SEC] [--limit N]\n'
        return 0 ;;
      *)
        if [[ -z "$target" ]]; then target="$1"; fi
        shift ;;
    esac
  done

  heading "HOST FINDER"
  hr 60

  if [[ -z "$target" ]]; then
    target=$(prompt "Domain or IP")
  fi
  target="${target// /}"
  if [[ -z "$target" ]]; then
    err "no target given"
    return 1
  fi
  target="${target#*://}"
  target="${target%%/*}"
  target="${target%.}"
  target="${target,,}"
  if ! is_valid_target "$target"; then
    err "invalid target: ${target}"
    return 1
  fi

  [[ "$conc" =~ ^[0-9]+$ ]] && (( conc > 0 )) || conc=10
  [[ "$timeout" =~ ^[0-9]+$ ]] && (( timeout > 0 )) || timeout=8
  [[ "$limit" =~ ^[0-9]+$ ]] && (( limit > 0 )) || limit=100

  local domain='' ip='' ptr=''
  if is_ip "$target"; then
    ip="$target"
  else
    domain="$target"
  fi

  info "Target: ${C_BOLD}${target}${C_RESET}"

  # --- forward records ----------------------------------------------------
  local -a a_recs=() aaaa_recs=() cname_recs=()
  local r
  if [[ -z "$ip" ]]; then
    local -a raw_recs=()
    mapfile -t raw_recs < <(dns_query "$domain" A 2>/dev/null || true)
    for r in ${raw_recs[@]+"${raw_recs[@]}"}; do
      is_ipv4 "$r" && a_recs+=("$r")
    done
    mapfile -t raw_recs < <(dns_query "$domain" AAAA 2>/dev/null || true)
    for r in ${raw_recs[@]+"${raw_recs[@]}"}; do
      is_ipv6 "$r" && aaaa_recs+=("$r")
    done
    mapfile -t cname_recs < <(dns_query "$domain" CNAME 2>/dev/null || true)
    if (( ${#cname_recs[@]} > 0 )); then
      local cname="${cname_recs[0]%.}"
      if (( ${#a_recs[@]} == 0 && ${#aaaa_recs[@]} == 0 )); then
        mapfile -t raw_recs < <(dns_query "$cname" A 2>/dev/null || true)
        for r in ${raw_recs[@]+"${raw_recs[@]}"}; do
          is_ipv4 "$r" && a_recs+=("$r")
        done
      fi
    fi
    ip="${a_recs[0]:-${aaaa_recs[0]:-}}"
  fi

  if [[ -z "$ip" ]]; then
    err "could not resolve ${domain}"
    return 1
  fi

  ptr=$(host_ptr "$ip" || true)

  printf '\n%sForward%s\n' "$C_BOLD" "$C_RESET"
  if (( ${#a_recs[@]} == 0 && ${#aaaa_recs[@]} == 0 && ${#cname_recs[@]} == 0 )); then
    printf '  %sgiven as an address, no lookup needed%s\n' "$C_DIM" "$C_RESET"
  fi
  for r in ${a_recs[@]+"${a_recs[@]}"}; do
    printf '  %-5s %s\n' "A" "$r"
  done
  for r in ${aaaa_recs[@]+"${aaaa_recs[@]}"}; do
    printf '  %-5s %s\n' "AAAA" "$r"
  done
  for r in ${cname_recs[@]+"${cname_recs[@]}"}; do
    printf '  %-5s %s\n' "CNAME" "$r"
  done
  if [[ -n "$ptr" ]]; then
    printf '  %-5s %s\n' "PTR" "$ptr"
  fi

  # --- passive reverse ----------------------------------------------------
  printf '\n%sReverse hosts%s %s(names seen on %s, passive)%s\n' \
    "$C_BOLD" "$C_RESET" "$C_DIM" "$ip" "$C_RESET"
  printf '  %squerying passive DNS...%s\n' "$C_DIM" "$C_RESET"

  local raw n src
  raw=$(host_reverse_passive "$ip" 2>/dev/null || true)

  local -A seen_rev=() src_count=()
  local -a rev_names=()
  while IFS=$'\t' read -r src n; do
    [[ -z "$src" ]] && continue
    n="${n%.}"
    n="${n,,}"
    [[ -z "$n" ]] && continue
    is_hostname "$n" || continue
    src_count["$src"]=$(( ${src_count[$src]:-0} + 1 ))
    [[ -n "${seen_rev[$n]:-}" ]] && continue
    seen_rev["$n"]=1
    rev_names+=("$n")
  done <<< "$raw"

  printf '  %-13s %s names\n' "mnemonic.no" "${src_count[m]:-0}"
  printf '  %-13s %s names\n' "hackertarget" "${src_count[h]:-0}"

  if (( ${#rev_names[@]} == 0 )); then
    printf '\n  %snothing found (the sources rate limit and prune old records)%s\n' \
      "$C_DIM" "$C_RESET"
  else
    local -a sorted_rev=()
    mapfile -t sorted_rev < <(printf '%s\n' "${rev_names[@]}" | sort)
    printf '\n  %s unique hostnames\n' "${#sorted_rev[@]}"
    local shown=0 colour
    for n in "${sorted_rev[@]}"; do
      (( shown >= 40 )) && break
      if [[ -n "$domain" && ( "$n" == "$domain" || "$n" == *".${domain}" ) ]]; then
        colour="$C_GREEN"
      else
        colour="$C_RESET"
      fi
      printf '  %s%s%s\n' "$colour" "$n" "$C_RESET"
      shown=$((shown + 1))
    done
    if (( ${#sorted_rev[@]} > shown )); then
      printf '  %s... and %s more%s\n' "$C_DIM" "$(( ${#sorted_rev[@]} - shown ))" "$C_RESET"
    fi
  fi

  # --- active virtual host probing ----------------------------------------
  local different_count=0 failed_count=0 probed=0
  if (( probe )); then
    printf '\n%sVirtual hosts%s %s(active)%s\n' "$C_BOLD" "$C_RESET" "$C_YELLOW" "$C_RESET"

    local -A seen_vh=()
    local -a vhosts=()
    local label
    # Hostnames already seen on this address come first, they are the most
    # promising candidates for a forgotten vhost.
    for n in ${rev_names[@]+"${rev_names[@]}"}; do
      (( ${#vhosts[@]} >= limit )) && break
      [[ -n "${seen_vh[$n]:-}" ]] && continue
      seen_vh["$n"]=1
      vhosts+=("$n")
    done
    if [[ -n "$domain" ]]; then
      if [[ -z "$wordlist" ]]; then
        wordlist=$(wordlist_file "subdomains.txt" || true)
      fi
      if [[ -n "$wordlist" && -f "$wordlist" ]]; then
        while IFS= read -r label || [[ -n "$label" ]]; do
          (( ${#vhosts[@]} >= limit )) && break
          label="${label%$'\r'}"
          label="${label,,}"
          [[ -z "$label" ]] && continue
          [[ "$label" == \#* ]] && continue
          [[ "$label" == *.* ]] && continue
          n="${label}.${domain}"
          is_hostname "$n" || continue
          [[ -n "${seen_vh[$n]:-}" ]] && continue
          seen_vh["$n"]=1
          vhosts+=("$n")
        done < "$wordlist"
      else
        warn "no subdomain wordlist found, probing passive names only"
      fi
    fi

    if (( ${#vhosts[@]} == 0 )); then
      warn "nothing to probe"
    elif ! confirm "Send ${#vhosts[@]} Host-header probes to ${ip}?"; then
      warn "vhost probing skipped"
    else
      local base_name baseline b_code b_size b_scheme
      if [[ -n "$domain" ]]; then
        base_name="digger-nope-$$-${RANDOM}.${domain}"
      else
        base_name="digger-nope-$$-${RANDOM}.invalid"
      fi
      baseline=$(host_probe_vhost "$base_name" "$ip" "$timeout")
      IFS=$'\t' read -r _ b_code b_size b_scheme <<< "$baseline"
      printf '  baseline    : %s %s (%s)\n' "$b_code" "$(human_size "$b_size")" "$b_scheme"
      printf '  probing     : %s names, %s workers\n' "${#vhosts[@]}" "$conc"

      local rawv
      rawv=$(printf '%s\n' "${vhosts[@]}" | host_probe_all "$ip" "$conc" "$timeout")

      local -a different=() failed=()
      local vh code size scheme diff
      while IFS=$'\t' read -r vh code size scheme; do
        [[ -z "$vh" ]] && continue
        probed=$((probed + 1))
        if [[ "$code" == '000' ]]; then
          failed+=("${vh}|${code}|${size}|${scheme}")
          failed_count=$((failed_count + 1))
          continue
        fi
        diff=$(( size - b_size ))
        (( diff < 0 )) && diff=$(( -diff ))
        if [[ "$code" != "$b_code" ]] || (( diff > 32 )); then
          different+=("${vh}|${code}|${size}|${scheme}")
          different_count=$((different_count + 1))
        fi
      done <<< "$rawv"

      printf '\n%sResults%s\n' "$C_BOLD" "$C_RESET"
      printf '  probed %s, %s answered differently, %s unreachable\n' \
        "$probed" "$different_count" "$failed_count"

      if [[ "$b_code" == '000' ]]; then
        printf '  %sthe address did not answer over HTTP or HTTPS, no baseline to compare%s\n' \
          "$C_DIM" "$C_RESET"
      elif (( ${#different[@]} > 0 )); then
        printf '\n%sNot the default response%s (%s)\n' "$C_GREEN" "$C_RESET" "${#different[@]}"
        shown=0
        local entry
        for entry in "${different[@]}"; do
          (( shown >= 40 )) && break
          IFS='|' read -r vh code size scheme <<< "$entry"
          printf '  %s%-4s%s %-44s %10s  %s\n' \
            "$C_GREEN" "$code" "$C_RESET" "$vh" "$(human_size "$size")" "$scheme"
          shown=$((shown + 1))
        done
        if (( ${#different[@]} > shown )); then
          printf '  %s... and %s more%s\n' "$C_DIM" "$(( ${#different[@]} - shown ))" "$C_RESET"
        fi
      else
        printf '  %severything replied like the default vhost%s\n' "$C_DIM" "$C_RESET"
      fi
    fi
  fi

  # --- summary ------------------------------------------------------------
  printf '\n%sSummary%s\n' "$C_BOLD" "$C_RESET"
  printf '  Address      : %s\n' "$ip"
  [[ -n "$ptr" ]] && printf '  PTR          : %s\n' "$ptr"
  printf '  Reverse names: %s\n' "${#rev_names[@]}"
  printf '  Vhost probes : %s\n' "$probed"
  return 0
}

# --- Module 4: Port Scanner ------------------------------------------------
# Ports probed by the /dev/tcp fallback when nmap is not installed.
SCAN_FALLBACK_PORTS=(21 22 23 25 53 80 110 111 135 139 143 161 389 443 445 465
  500 512 513 514 515 548 587 631 636 993 995 1080 1433 1521 1723 2049 2082
  2083 2181 2375 2376 3000 3306 3389 4444 5000 5432 5601 5672 5900 5984 6379
  6443 7001 8000 8008 8080 8081 8443 8888 9000 9090 9200 9300 11211 27017
  27018 50000)

# Service name for a port number, from a small built-in table and then the
# system services database.
scan_service_name() {
  local p="$1" name=''
  case "$p" in
    21) name=ftp ;; 22) name=ssh ;; 23) name=telnet ;; 25) name=smtp ;;
    53) name=domain ;; 80) name=http ;; 110) name=pop3 ;; 111) name=rpcbind ;;
    135) name=msrpc ;; 139) name=netbios-ssn ;; 143) name=imap ;; 161) name=snmp ;;
    389) name=ldap ;; 443) name=https ;; 445) name=microsoft-ds ;; 465) name=smtps ;;
    512) name='exec' ;; 513) name=login ;; 514) name='shell' ;; 515) name=printer ;;
    548) name=afp ;; 587) name=submission ;; 631) name=ipp ;; 636) name=ldaps ;;
    993) name=imaps ;; 995) name=pop3s ;; 1080) name=socks ;;
    1433) name=ms-sql-s ;; 1521) name=oracle ;; 1723) name=pptp ;;
    2049) name=nfs ;; 2082) name=cpanel ;; 2083) name=cpanel-ssl ;;
    2181) name=zookeeper ;; 2375) name=docker ;; 2376) name=docker-ssl ;;
    3000) name=node ;; 3306) name=mysql ;; 3389) name=ms-wbt-server ;;
    4444) name=metasploit ;; 5000|8000|8008|8081|8888|9090|50000) name=http-alt ;;
    5432) name=postgresql ;; 5601) name=kibana ;; 5672) name=amqp ;;
    5900) name=vnc ;; 5984) name=couchdb ;; 6379) name=redis ;;
    6443) name=k8s-api ;; 7001) name=weblogic ;; 8080) name=http-proxy ;;
    8443) name=https-alt ;; 9200|9300) name=elasticsearch ;;
    11211) name=memcached ;; 27017|27018) name=mongodb ;;
  esac
  if [[ -z "$name" ]]; then
    name=$(getent services "$p/tcp" 2>/dev/null | awk '{print $1; exit}' || true)
  fi
  printf '%s' "${name:-unknown}"
}

# Expand "80,443,8000-8100" into one port per line.
scan_expand_ports() {
  local spec="$1"
  local -a parts=() out=()
  local part lo hi i
  IFS=',' read -ra parts <<< "$spec"
  for part in ${parts[@]+"${parts[@]}"}; do
    part="${part// /}"
    [[ -z "$part" ]] && continue
    if [[ "$part" =~ ^([0-9]+)-([0-9]+)$ ]]; then
      lo="${BASH_REMATCH[1]}"
      hi="${BASH_REMATCH[2]}"
      (( lo < 1 )) && lo=1
      (( hi > 65535 )) && hi=65535
      for (( i = lo; i <= hi; i++ )); do out+=("$i"); done
    elif [[ "$part" =~ ^[0-9]+$ ]]; then
      out+=("$part")
    fi
  done
  (( ${#out[@]} == 0 )) && return 0
  printf '%s\n' "${out[@]}"
}

# Can we open a TCP connection to host:port? Used only without nmap.
scan_probe_tcp() {
  local host="$1" port="$2" timeout="${3:-2}"
  if have timeout; then
    timeout "$timeout" bash -c "exec 3<>/dev/tcp/${host}/${port}" \
      </dev/null >/dev/null 2>&1
    return $?
  fi
  ( exec 3<>"/dev/tcp/${host}/${port}" ) </dev/null >/dev/null 2>&1
}

# Brute the fallback port list, keeping at most <conc> probes in flight.
scan_fallback_all() {
  local host="$1" timeout="$2" conc="$3"
  shift 3
  local -a ports=("$@") pids=()
  local p
  for p in ${ports[@]+"${ports[@]}"}; do
    {
      if scan_probe_tcp "$host" "$p" "$timeout"; then
        printf '%s\topen\n' "$p"
      fi
    } &
    pids+=($!)
    if (( ${#pids[@]} >= conc )); then
      wait "${pids[0]}" 2>/dev/null || true
      pids=("${pids[@]:1}")
    fi
  done
  wait 2>/dev/null || true
}

mod_scan() {
  local target='' ports_spec='' top=1000 conc=50 timeout=2 overall=300
  local version=0

  while (( $# > 0 )); do
    case "$1" in
      --ports)       ports_spec="${2:-}"; shift 2 || shift ;;
      --top-ports)   top="${2:-1000}"; shift 2 || shift ;;
      --fast)        top=100; shift ;;
      --version)     version=1; shift ;;
      --timeout)     timeout="${2:-2}"; shift 2 || shift ;;
      --max-time)    overall="${2:-300}"; shift 2 || shift ;;
      --concurrency) conc="${2:-50}"; shift 2 || shift ;;
      -y|--yes)      ASSUME_YES=1; shift ;;
      -h|--help)
        printf 'usage: digger.sh scan <host|ip> [--ports SPEC] [--top-ports N] [--fast] [--version] [--timeout SEC] [--max-time SEC] [--concurrency N]\n'
        return 0 ;;
      *)
        if [[ -z "$target" ]]; then target="$1"; fi
        shift ;;
    esac
  done

  heading "PORT SCANNER"
  hr 60

  if [[ -z "$target" ]]; then
    target=$(prompt "Host or IP")
  fi
  target="${target// /}"
  if [[ -z "$target" ]]; then
    err "no target given"
    return 1
  fi
  target="${target#*://}"
  target="${target%%/*}"
  target="${target%.}"
  target="${target,,}"
  if ! is_valid_target "$target"; then
    err "invalid target: ${target}"
    return 1
  fi

  [[ "$conc" =~ ^[0-9]+$ ]] && (( conc > 0 )) || conc=50
  [[ "$timeout" =~ ^[0-9]+$ ]] && (( timeout > 0 )) || timeout=2
  [[ "$overall" =~ ^[0-9]+$ ]] && (( overall > 0 )) || overall=300
  [[ "$top" =~ ^[0-9]+$ ]] && (( top > 0 )) || top=1000

  local ip=''
  if is_ip "$target"; then
    ip="$target"
  else
    ip=$(resolve_host "$target" || true)
  fi
  if [[ -z "$ip" ]]; then
    err "could not resolve ${target}"
    return 1
  fi

  local engine='bash'
  have nmap && engine='nmap'

  info "Target: ${C_BOLD}${target}${C_RESET} (${ip})"

  local scope
  if [[ -n "$ports_spec" ]]; then
    scope="ports ${ports_spec}"
  elif [[ "$engine" == 'nmap' ]]; then
    scope="top ${top} TCP ports"
  else
    scope="${#SCAN_FALLBACK_PORTS[@]} common TCP ports"
  fi

  printf '\n%sScan%s\n' "$C_BOLD" "$C_RESET"
  if [[ "$engine" == 'nmap' ]]; then
    printf '  engine      : nmap, TCP connect scan (-sT, no root needed)\n'
    (( version )) && printf '  detection   : version probing enabled\n'
  else
    printf '  engine      : bash /dev/tcp fallback %s(nmap not installed)%s\n' \
      "$C_DIM" "$C_RESET"
  fi
  printf '  scope       : %s\n' "$scope"

  if ! confirm "This sends a TCP connect scan to ${ip}. Continue?"; then
    warn "aborted"
    return 0
  fi

  local start elapsed out line
  start=$(date +%s)
  local -a open_ports=()
  local closed=0 status=''

  if [[ "$engine" == 'nmap' ]]; then
    local -a nmap_args=(-sT -Pn -n -T4 -oG -)
    if [[ -n "$ports_spec" ]]; then
      nmap_args+=(-p "$ports_spec")
    else
      nmap_args+=(--top-ports "$top")
    fi
    if (( version )); then
      nmap_args+=(-sV --version-light)
    fi
    nmap_args+=("$ip")

    if have timeout; then
      out=$(timeout "$overall" nmap "${nmap_args[@]}" 2>&1) || true
    else
      out=$(nmap "${nmap_args[@]}" 2>&1) || true
    fi

    local ports_field entries entry ignored
    local pnum pstate pproto _ psvc _ pver _
    while IFS= read -r line; do
      case "$line" in
        Host:*'Status:'*)
          status=$(printf '%s' "$line" | sed -n 's/.*Status: \([A-Za-z]*\).*/\1/p')
          ;;
        Host:*'Ports:'*)
          ports_field="${line#*Ports: }"
          ports_field="${ports_field%%$'\t'*}"
          IFS=',' read -ra entries <<< "$ports_field"
          for entry in ${entries[@]+"${entries[@]}"}; do
            entry="${entry# }"
            IFS='/' read -r pnum pstate pproto _ psvc _ pver _ <<< "$entry"
            [[ "$pstate" == 'open' ]] || continue
            open_ports+=("${pnum}/${pproto}|${psvc:-unknown}|${pver:-}")
          done
          ignored=$(printf '%s' "$line" | sed -n 's/.*Ignored State: [a-z]* (\([0-9]*\)).*/\1/p')
          [[ -n "$ignored" ]] && closed="$ignored"
          ;;
      esac
    done <<< "$out"

    if [[ -z "$status" ]]; then
      warn "nmap returned no host block"
      printf '%s\n' "$out" | sed -n '1,5p'
    fi
  else
    if ! have timeout; then
      warn "no 'timeout' command, probes may stall on filtered ports"
    fi
    local -a scan_ports=("${SCAN_FALLBACK_PORTS[@]}")
    if [[ -n "$ports_spec" ]]; then
      mapfile -t scan_ports < <(scan_expand_ports "$ports_spec")
      if (( ${#scan_ports[@]} == 0 )); then
        err "invalid port list: ${ports_spec}"
        return 1
      fi
    fi
    out=$(scan_fallback_all "$ip" "$timeout" "$conc" "${scan_ports[@]}")
    local p
    while IFS=$'\t' read -r p line; do
      [[ -z "$p" ]] && continue
      open_ports+=("${p}/tcp|$(scan_service_name "$p")|")
    done <<< "$out"
    closed=$(( ${#scan_ports[@]} - ${#open_ports[@]} ))
  fi

  elapsed=$(( $(date +%s) - start ))

  # --- results ------------------------------------------------------------
  printf '\n%sResults%s\n' "$C_BOLD" "$C_RESET"
  [[ -n "$status" ]] && printf '  host status : %s\n\n' "$status"

  if (( ${#open_ports[@]} == 0 )); then
    printf '  %sno open ports found%s\n' "$C_DIM" "$C_RESET"
  else
    local entry2 port state service ver
    local -a sorted_ports=()
    mapfile -t sorted_ports < <(printf '%s\n' "${open_ports[@]}" | sort -t/ -k1,1n)
    printf '  %s%-9s %-6s %-14s %s%s\n' "$C_BOLD" "PORT" "STATE" "SERVICE" "VERSION" "$C_RESET"
    for entry2 in ${sorted_ports[@]+"${sorted_ports[@]}"}; do
      port="${entry2%%|*}"
      entry2="${entry2#*|}"
      service="${entry2%%|*}"
      ver="${entry2#*|}"
      printf '  %s%-9s%s %-6s %-14s %s\n' "$C_GREEN" "$port" "$C_RESET" "open" "$service" "$ver"
    done
  fi

  # --- summary ------------------------------------------------------------
  printf '\n%sSummary%s\n' "$C_BOLD" "$C_RESET"
  printf '  Target  : %s (%s)\n' "$target" "$ip"
  if [[ "$engine" == 'nmap' ]]; then
    printf '  Engine  : nmap (-sT)\n'
  else
    printf '  Engine  : bash /dev/tcp\n'
  fi
  printf '  Scope   : %s\n' "$scope"
  printf '  Open    : %s\n' "${#open_ports[@]}"
  printf '  Not open: %s\n' "${closed:-0}"
  printf '  Elapsed : %ss\n' "$elapsed"
  if [[ "$engine" != 'nmap' ]]; then
    printf '  %sinstall nmap for a full 1000 port scan and version detection%s\n' \
      "$C_DIM" "$C_RESET"
  fi
  return 0
}

# --- Module 14: API and Secret Discovery -----------------------------------
SECRET_LEVELS=()
SECRET_LABELS=()
SECRET_REGEXES=()
SECRET_COMBINED=''

secrets_pattern() {
  SECRET_LEVELS+=("$1")
  SECRET_LABELS+=("$2")
  SECRET_REGEXES+=("$3")
  if [[ -n "$SECRET_COMBINED" ]]; then
    SECRET_COMBINED="${SECRET_COMBINED}|(${3})"
  else
    SECRET_COMBINED="(${3})"
  fi
}

secrets_init_patterns() {
  (( ${#SECRET_REGEXES[@]} > 0 )) && return 0

  # High confidence: the string only makes sense as a live credential.
  secrets_pattern high "private key block" \
    '-----BEGIN [A-Z ]*PRIVATE KEY-----'
  secrets_pattern high "AWS access key id" \
    'AKIA[0-9A-Z]{16}'
  secrets_pattern high "AWS temporary key id" \
    'ASIA[0-9A-Z]{16}'
  secrets_pattern high "AWS secret access key" \
    'aws_secret_access_key[^A-Za-z0-9]{0,6}[:=][^A-Za-z0-9]{0,3}[A-Za-z0-9/+=]{40}'
  secrets_pattern high "Google API key" \
    'AIza[0-9A-Za-z_-]{35}'
  secrets_pattern high "GitHub token" \
    'gh[pousr]_[A-Za-z0-9]{36,}'
  secrets_pattern high "GitHub fine grained token" \
    'github_pat_[A-Za-z0-9_]{22,}'
  secrets_pattern high "Slack token" \
    'xox[baprs]-[0-9A-Za-z-]{10,}'
  secrets_pattern high "Stripe live key" \
    'sk_live_[0-9A-Za-z]{20,}'
  secrets_pattern high "SendGrid key" \
    'SG[.][A-Za-z0-9_-]{16,}[.][A-Za-z0-9_-]{16,}'
  secrets_pattern high "Mailgun key" \
    'key-[0-9a-zA-Z]{32}\b'
  secrets_pattern high "npm token" \
    'npm_[A-Za-z0-9]{36}'
  secrets_pattern high "Shopify token" \
    'shp(at|ca|pa)_[0-9a-fA-F]{32}'
  secrets_pattern high "Discord webhook" \
    'discord[.]com/api/webhooks/[0-9]+/[A-Za-z0-9_-]+'
  secrets_pattern high "OpenAI style key" \
    'sk-(proj-)?[A-Za-z0-9]{32,}'

  # Medium: credential shaped, but common in public code too.
  secrets_pattern medium "Twilio account SID" \
    'AC[0-9a-f]{32}'
  secrets_pattern medium "Twilio API key" \
    'SK[0-9a-f]{32}'
  secrets_pattern medium "JSON web token" \
    'eyJ[A-Za-z0-9_-]{10,}[.][A-Za-z0-9_-]{10,}[.][A-Za-z0-9_-]{5,}'
  secrets_pattern medium "bearer token" \
    'Bearer[[:space:]]+[A-Za-z0-9_.=+/-]{20,}'
  secrets_pattern medium "credential in URL" \
    'https?://[^/[:space:]:@]+:[^/[:space:]:@]+@'
  secrets_pattern medium "api key assignment" \
    '(api[_-]?key|apikey|access[_-]?token|auth[_-]?token|client[_-]?secret|secret[_-]?key)[^A-Za-z0-9]{0,6}[:=][^A-Za-z0-9]{0,3}[A-Za-z0-9_./+=-]{16,}'
  secrets_pattern medium "firebase database" \
    'https?://[A-Za-z0-9-]+[.]firebaseio[.]com'
  secrets_pattern medium "S3 bucket URL" \
    '[A-Za-z0-9._-]+[.]s3[.-][A-Za-z0-9-]*[.]?amazonaws[.]com'
  secrets_pattern medium "Azure blob storage" \
    '[A-Za-z0-9]{3,24}[.]blob[.]core[.]windows[.]net'

  # Low: not secrets, but useful leads for the next step.
  secrets_pattern low "internal IP" \
    '\b10([.][0-9]{1,3}){3}\b|\b192[.]168([.][0-9]{1,3}){2}\b|\b172[.](1[6-9]|2[0-9]|3[01])([.][0-9]{1,3}){2}\b'
  secrets_pattern low "API path" \
    '/(api|rest|graphql|v[0-9]+)/[A-Za-z0-9_./{}-]{2,}'
  secrets_pattern low "source map" \
    '[A-Za-z0-9._/-]+[.]js[.]map'
}

# Show enough of a value to recognise it without dumping the whole secret.
# URLs, paths and key headers are locations, not credentials, so they stay
# readable; everything else is truncated.
secrets_mask() {
  local s="$1"
  case "$s" in
    *://*|/*|'-----BEGIN'*) printf '%s' "$s"; return 0 ;;
  esac
  if (( ${#s} > 16 )); then
    printf '%s...%s' "${s:0:6}" "${s: -4}"
  else
    printf '%s' "$s"
  fi
}

mod_secrets() {
  local target='' depth=2 maxpages=10 maxscripts=25 delay=0.2

  while (( $# > 0 )); do
    case "$1" in
      --depth)       depth="${2:-2}"; shift 2 || shift ;;
      --max-pages)   maxpages="${2:-10}"; shift 2 || shift ;;
      --max-scripts) maxscripts="${2:-25}"; shift 2 || shift ;;
      --delay)       delay="${2:-0.2}"; shift 2 || shift ;;
      -y|--yes)      ASSUME_YES=1; shift ;;
      -h|--help)
        printf 'usage: digger.sh secrets <url> [--depth N] [--max-pages N] [--max-scripts N] [--delay S]\n'
        return 0 ;;
      *)
        if [[ -z "$target" ]]; then target="$1"; fi
        shift ;;
    esac
  done

  heading "API AND SECRET DISCOVERY"
  hr 60

  if [[ -z "$target" ]]; then
    target=$(prompt "Start URL")
  fi
  target="${target// /}"
  if [[ -z "$target" ]]; then
    err "no URL given"
    return 1
  fi
  [[ "$target" != http://* && "$target" != https://* ]] && target="https://${target}"
  target="${target%/}"

  local hostpart="${target#*://}"
  hostpart="${hostpart%%/*}"
  hostpart="${hostpart%%:*}"
  if ! is_hostname "$hostpart" && ! is_ip "$hostpart"; then
    err "invalid URL: ${target}"
    return 1
  fi

  [[ "$depth" =~ ^[0-9]+$ ]] || depth=2
  [[ "$maxpages" =~ ^[0-9]+$ ]] && (( maxpages > 0 )) || maxpages=10
  [[ "$maxscripts" =~ ^[0-9]+$ ]] || maxscripts=25
  [[ "$delay" =~ ^[0-9.]+$ ]] || delay=0.2

  secrets_init_patterns

  info "Target: ${C_BOLD}${target}${C_RESET}"
  printf '  Limits      : depth %s, %s pages, %s scripts\n' \
    "$depth" "$maxpages" "$maxscripts"
  printf '  Patterns    : %s (high %s, medium %s, low %s)\n' \
    "${#SECRET_REGEXES[@]}" \
    "$(printf '%s\n' "${SECRET_LEVELS[@]}" | grep -c '^high$' || true)" \
    "$(printf '%s\n' "${SECRET_LEVELS[@]}" | grep -c '^medium$' || true)" \
    "$(printf '%s\n' "${SECRET_LEVELS[@]}" | grep -c '^low$' || true)"

  if ! confirm "This fetches pages and scripts from ${target}. Continue?"; then
    warn "aborted"
    return 0
  fi

  # --- crawl --------------------------------------------------------------
  local base_host base_suffix
  base_host=$(url_host "$target")
  base_suffix="$base_host"
  if [[ "$base_host" == *.*.* ]]; then
    base_suffix="${base_host#*.}"
  fi

  local -A seen_page=()
  local -a queue=("0|${target}") corpus_urls=() corpus_bodies=() script_urls=()
  local -A seen_script=()
  local pages_n=0 scripts_n=0
  local entry d u body link abs ahost ext

  printf '\n  %sfetching pages...%s\n' "$C_DIM" "$C_RESET"
  while (( ${#queue[@]} > 0 )); do
    entry="${queue[0]}"
    queue=("${queue[@]:1}")
    d="${entry%%|*}"
    u="${entry#*|}"
    (( d > depth )) && continue
    [[ -n "${seen_page[$u]:-}" ]] && continue
    (( pages_n >= maxpages )) && break
    seen_page["$u"]=1
    body=$(page_body "$u" 400000)
    [[ -z "$body" ]] && continue
    pages_n=$((pages_n + 1))
    corpus_urls+=("$u")
    corpus_bodies+=("$body")

    while IFS= read -r link; do
      [[ -z "$link" ]] && continue
      case "${link,,}" in
        javascript:*|mailto:*|tel:*|data:*|about:*|ftp:*|blob:*|file:*|'#'*) continue ;;
      esac
      abs=$(url_join "$u" "$link" || true)
      [[ -z "$abs" ]] && continue
      case "$abs" in http://*|https://*) ;; *) continue ;; esac
      abs="${abs%%#*}"
      ext="${abs%%\?*}"
      ahost=$(url_host "$abs")
      if [[ "${ext,,}" == *.js || "${ext,,}" == *.mjs ]]; then
        # Only own scripts: a third party CDN bundle is noise and we should
        # not go pulling files off unrelated hosts.
        if [[ "$ahost" == "$base_host" || "$ahost" == *".${base_suffix}" ]]; then
          if [[ -z "${seen_script[$abs]:-}" ]] && (( ${#script_urls[@]} < maxscripts )); then
            seen_script["$abs"]=1
            script_urls+=("$abs")
          fi
        fi
        continue
      fi
      if [[ "$ahost" == "$base_host" ]] && (( d < depth )) && [[ -z "${seen_page[$abs]:-}" ]]; then
        queue+=("$((d + 1))|${abs}")
      fi
    done < <(extract_links "$body")

    if gt_zero "$delay"; then sleep "$delay"; fi
  done

  if (( pages_n == 0 )); then
    warn "could not fetch any page from ${target}"
    return 1
  fi

  local su sbody
  if (( ${#script_urls[@]} > 0 )); then
    printf '  %sfetching %s scripts...%s\n' "$C_DIM" "${#script_urls[@]}" "$C_RESET"
    for su in ${script_urls[@]+"${script_urls[@]}"}; do
      sbody=$(page_body "$su" 600000)
      [[ -z "$sbody" ]] && continue
      scripts_n=$((scripts_n + 1))
      corpus_urls+=("$su")
      corpus_bodies+=("$sbody")
    done
  fi

  if (( scripts_n < ${#script_urls[@]} )); then
    printf '  %s%s of %s scripts could not be fetched%s\n' \
      "$C_DIM" "$(( ${#script_urls[@]} - scripts_n ))" "${#script_urls[@]}" "$C_RESET"
  fi

  # --- scan ---------------------------------------------------------------
  local -A seen_find=()
  local -a high=() medium=() low=()
  local i j label level value key matches m
  local total_matches=0

  for i in "${!corpus_urls[@]}"; do
    matches=$(printf '%s' "${corpus_bodies[$i]}" \
      | grep -oiE -- "$SECRET_COMBINED" 2>/dev/null \
      | head -n 400 | sort -u || true)
    [[ -z "$matches" ]] && continue
    while IFS= read -r m; do
      [[ -z "$m" ]] && continue
      total_matches=$((total_matches + 1))
      (( total_matches > 400 )) && break
      # Keep the pipe used as the field separator out of the stored value.
      m="${m//$'\t'/ }"
      m="${m//|/-}"
      label=''
      level=''
      for j in "${!SECRET_REGEXES[@]}"; do
        if [[ "$m" =~ ${SECRET_REGEXES[$j]} ]]; then
          label="${SECRET_LABELS[$j]}"
          level="${SECRET_LEVELS[$j]}"
          break
        fi
      done
      [[ -z "$label" ]] && continue
      value=$(secrets_mask "$m")
      key="${level}|${label}|${value}|${corpus_urls[$i]}"
      [[ -n "${seen_find[$key]:-}" ]] && continue
      seen_find["$key"]=1
      case "$level" in
        high)   high+=("${label}|${value}|${corpus_urls[$i]}") ;;
        medium) medium+=("${label}|${value}|${corpus_urls[$i]}") ;;
        *)      low+=("${label}|${value}|${corpus_urls[$i]}") ;;
      esac
    done <<< "$matches"
  done

  # --- findings -----------------------------------------------------------
  printf '\n%sFindings%s\n' "$C_BOLD" "$C_RESET"
  printf '  crawled %s pages and %s scripts, %s candidate strings\n' \
    "$pages_n" "$scripts_n" "$total_matches"

  local -a entries=()
  local colour title item l v s shown
  for spec in "high:${C_RED}:HIGH" "medium:${C_YELLOW}:MEDIUM" "low:${C_DIM}:LOW"; do
    IFS=':' read -r level colour title <<< "$spec"
    case "$level" in
      high)   entries=(${high[@]+"${high[@]}"}) ;;
      medium) entries=(${medium[@]+"${medium[@]}"}) ;;
      low)    entries=(${low[@]+"${low[@]}"}) ;;
    esac
    printf '\n%s%s%s (%s)\n' "$colour" "$title" "$C_RESET" "${#entries[@]}"
    if (( ${#entries[@]} == 0 )); then
      printf '  %snone%s\n' "$C_DIM" "$C_RESET"
      continue
    fi
    shown=0
    for item in "${entries[@]}"; do
      (( shown >= 30 )) && break
      IFS='|' read -r l v s <<< "$item"
      printf '  %-26s %-30s %s\n' "$l" "$v" "$s"
      shown=$((shown + 1))
    done
    if (( ${#entries[@]} > shown )); then
      printf '  %s... and %s more%s\n' "$C_DIM" "$(( ${#entries[@]} - shown ))" "$C_RESET"
    fi
  done

  # --- summary ------------------------------------------------------------
  printf '\n%sSummary%s\n' "$C_BOLD" "$C_RESET"
  printf '  Pages    : %s\n' "$pages_n"
  printf '  Scripts  : %s\n' "$scripts_n"
  printf '  High     : %s\n' "${#high[@]}"
  printf '  Medium   : %s\n' "${#medium[@]}"
  printf '  Low      : %s\n' "${#low[@]}"
  printf '  %slong values are truncated, confirm by hand before reporting%s\n' \
    "$C_DIM" "$C_RESET"
  return 0
}

mod_info() {
  local target="${1:-}"

  heading "INFO IP AND SITE"
  hr 60

  if [[ -z "$target" ]]; then
    target=$(prompt "IP address or hostname")
  fi
  target="${target// /}"
  target="${target,,}"

  if [[ -z "$target" ]]; then
    err "no target given"
    return 1
  fi
  if ! is_valid_target "$target"; then
    err "invalid target: ${target}"
    return 1
  fi

  if is_ip "$target"; then
    info_for_ip "$target"
  else
    info_for_site "$target"
  fi
}

info_for_ip() {
  local ip="$1"
  info "Target: ${C_BOLD}${ip}${C_RESET}"

  # --- geolocation -------------------------------------------------------
  local json country city region isp asn org lat lon tz
  json=$(http_get "https://ipwho.is/${ip}" "$HTTP_TIMEOUT" 1) || json=''
  if [[ -n "$json" ]]; then
    country=$(json_get "$json" '.country') || country=''
    region=$(json_get "$json" '.region') || region=''
    city=$(json_get "$json" '.city') || city=''
    isp=$(json_get "$json" '.connection.isp') || isp=''
    asn=$(json_get "$json" '.connection.asn') || asn=''
    org=$(json_get "$json" '.connection.org') || org=''
    lat=$(json_get "$json" '.latitude') || lat=''
    lon=$(json_get "$json" '.longitude') || lon=''
    tz=$(json_get "$json" '.timezone.id') || tz=''

    printf '\n%sLocation%s\n' "$C_BOLD" "$C_RESET"
    printf '  Country       : %s\n' "${country:-unknown}"
    printf '  Region        : %s\n' "${region:-unknown}"
    printf '  City          : %s\n' "${city:-unknown}"
    printf '  Coordinates   : %s, %s\n' "${lat:-?}" "${lon:-?}"
    printf '  Timezone      : %s\n' "${tz:-unknown}"

    printf '\n%sNetwork%s\n' "$C_BOLD" "$C_RESET"
    printf '  ISP           : %s\n' "${isp:-unknown}"
    printf '  Org           : %s\n' "${org:-unknown}"
    [[ -n "$asn" ]] && printf '  ASN           : AS%s\n' "$asn"
  else
    warn "geolocation source unavailable"
  fi

  # --- authoritative registration data ------------------------------------
  local rdap handle netname cidr prefix length rname rcountry start end rtype abuse
  rdap=$(rdap_get "ip/${ip}") || rdap=''
  if [[ -n "$rdap" ]]; then
    handle=$(json_get "$rdap" '.handle') || handle=''
    netname=$(json_get "$rdap" '.name') || netname=''
    start=$(json_get "$rdap" '.startAddress') || start=''
    end=$(json_get "$rdap" '.endAddress') || end=''
    rtype=$(json_get "$rdap" '.type') || rtype=''
    prefix=$(json_get "$rdap" '.cidr0_cidrs[0].v4prefix') || prefix=''
    length=$(json_get "$rdap" '.cidr0_cidrs[0].length') || length=''
    [[ -n "$prefix" && -n "$length" ]] && cidr="${prefix}/${length}"
    rname=$(rdap_role_field "$rdap" 'registrant' 'fn') || rname=$(rdap_role_field "$rdap" 'registrant' 'org') || rname=''
    abuse=$(rdap_role_field "$rdap" 'abuse' 'email') || abuse=''
    rcountry=$(json_get "$rdap" '.country') || rcountry=''

    printf '\n%sAllocation (RDAP)%s\n' "$C_BOLD" "$C_RESET"
    printf '  Net name      : %s\n' "${netname:-unknown}"
    printf '  Handle        : %s\n' "${handle:-unknown}"
    [[ -n "$rtype" ]] && printf '  Type          : %s\n' "$rtype"
    printf '  Range         : %s - %s\n' "${start:-?}" "${end:-?}"
    [[ -n "$cidr" ]] && printf '  CIDR          : %s\n' "$cidr"
    [[ -n "$rname" ]] && printf '  Registrant    : %s\n' "$rname"
    [[ -n "$rcountry" ]] && printf '  Country       : %s\n' "$rcountry"
    [[ -n "$abuse" ]] && printf '  Abuse contact : %s\n' "$abuse"
  else
    warn "RDAP record unavailable"
  fi

  # --- reverse DNS --------------------------------------------------------
  local ptr=''
  if have dig; then
    ptr=$(dig +short -x "$ip" +time=4 +tries=1 2>/dev/null | tail -n1 || true)
  fi
  if [[ -z "$ptr" ]] && is_ipv4 "$ip"; then
    local rev4 json
    rev4=$(printf '%s' "$ip" | awk -F. '{print $4"."$3"."$2"."$1}')
    json=$(http_get "https://dns.google/resolve?name=${rev4}.in-addr.arpa&type=PTR" "$HTTP_TIMEOUT" 1) || json=''
    if [[ -n "$json" ]]; then
      ptr=$(json_get "$json" '.Answer[0].data') || ptr=''
      ptr="${ptr%.}"
    fi
  fi
  printf '\n%sReverse DNS%s\n' "$C_BOLD" "$C_RESET"
  if [[ -n "$ptr" ]]; then
    printf '  PTR           : %s\n' "$ptr"
  else
    printf '  PTR           : %snone%s\n' "$C_DIM" "$C_RESET"
  fi

  # --- shared hosting / co-hosted domains ----------------------------------
  local rev csv
  rev=$(http_get "https://api.hackertarget.com/reverseiplookup/?q=${ip}" "$HTTP_TIMEOUT" 1) || rev=''
  printf '\n%sHosts on this IP%s\n' "$C_BOLD" "$C_RESET"
  if [[ -n "$rev" ]] && ! printf '%s' "$rev" | grep -qi 'API count exceeded'; then
    csv=$(printf '%s' "$rev" | grep -E '^[A-Za-z0-9_.-]+\.[A-Za-z]{2,},' | head -n 40 || true)
    if [[ -n "$csv" ]]; then
      printf '%s\n' "$csv" | while IFS=',' read -r host _; do
        [[ -n "$host" ]] && printf '  %s\n' "$host"
      done
      local count
      count=$(printf '%s\n' "$csv" | grep -c . || true)
      printf '  %s(%s shown)%s\n' "$C_DIM" "$count" "$C_RESET"
    else
      printf '  %snone found%s\n' "$C_DIM" "$C_RESET"
    fi
  else
    printf '  %ssource unavailable%s\n' "$C_DIM" "$C_RESET"
  fi

  # --- quick web service probe --------------------------------------------
  printf '\n%sWeb services%s\n' "$C_BOLD" "$C_RESET"
  local port scheme code found_svc=0
  for port in 80 443 8080 8443; do
    scheme="http"
    [[ "$port" == "443" || "$port" == "8443" ]] && scheme="https"
    code=$(final_status "${scheme}://${ip}:${port}" 6)
    if [[ "$code" =~ ^[1-5][0-9][0-9]$ ]] && [[ "$code" != "000" ]]; then
      printf '  %-6s %s -> HTTP %s\n' "$port" "$scheme" "$code"
      found_svc=1
    fi
  done
  (( found_svc )) || printf '  %sno web service on common ports%s\n' "$C_DIM" "$C_RESET"
  return 0
}

info_for_site() {
  local host="$1"
  info "Target: ${C_BOLD}${host}${C_RESET}"

  # --- resolution ---------------------------------------------------------
  local ip
  ip=$(resolve_host "$host" || true)
  printf '\n%sResolution%s\n' "$C_BOLD" "$C_RESET"
  if [[ -n "$ip" ]]; then
    printf '  IP address    : %s\n' "$ip"
    if is_private_ip "$ip"; then
      printf '  Scope         : %sprivate / internal%s\n' "$C_YELLOW" "$C_RESET"
    else
      printf '  Scope         : %spublic%s\n' "$C_GREEN" "$C_RESET"
    fi
  else
    printf '  IP address    : %sunresolved%s\n' "$C_YELLOW" "$C_RESET"
  fi

  # --- HTTP response ------------------------------------------------------
  local url="https://${host}" code headers
  code=$(final_status "$url" 12)
  if [[ ! "$code" =~ ^[1-5] ]]; then
    url="http://${host}"
    code=$(final_status "$url" 12)
  fi
  headers=$(final_headers "$url" 12)

  printf '\n%sHTTP%s\n' "$C_BOLD" "$C_RESET"
  printf '  URL           : %s\n' "$url"
  if [[ "$code" =~ ^[1-5] ]]; then
    printf '  Status        : %s%s%s\n' "$C_BOLD" "$code" "$C_RESET"
  else
    printf '  Status        : %sunreachable%s\n' "$C_YELLOW" "$C_RESET"
  fi
  local hv
  hv=$(header_value "$headers" 'server')
  [[ -n "$hv" ]] && printf '  Server        : %s\n' "$hv"
  hv=$(header_value "$headers" 'x-powered-by')
  [[ -n "$hv" ]] && printf '  Powered by    : %s\n' "$hv"
  hv=$(header_value "$headers" 'location')
  [[ -n "$hv" ]] && printf '  Redirects to  : %s\n' "$hv"
  hv=$(header_value "$headers" 'content-type')
  [[ -n "$hv" ]] && printf '  Content type  : %s\n' "$hv"

  # --- title --------------------------------------------------------------
  local body title
  body=$(page_body "$url" 400000)
  title=$(printf '%s' "$body" | tr '\n' ' ' | grep -oiE '<title[^>]*>[^<]{0,300}' | head -n1 \
    | sed -E 's/<title[^>]*>//I' || true)
  printf '\n%sPage%s\n' "$C_BOLD" "$C_RESET"
  printf '  Title         : %s\n' "${title:-n/a}"

  # --- technology ---------------------------------------------------------
  local tech
  tech=$(detect_tech "$headers" "$body" || true)
  printf '\n%sTechnology%s\n' "$C_BOLD" "$C_RESET"
  if [[ -n "$tech" ]]; then
    printf '%s\n' "$tech"
  else
    printf '  %snothing fingerprintable%s\n' "$C_DIM" "$C_RESET"
  fi

  # --- security headers ---------------------------------------------------
  printf '\n%sSecurity headers%s\n' "$C_BOLD" "$C_RESET"
  local hdr hdr_missing=0
  for hdr in 'Strict-Transport-Security' 'Content-Security-Policy' 'X-Frame-Options' \
           'X-Content-Type-Options' 'Referrer-Policy' 'Permissions-Policy'; do
    if header_present "$headers" "$hdr"; then
      printf '  %s[+]%s %s\n' "$C_GREEN" "$C_RESET" "$hdr"
    else
      printf '  %s[-]%s %s %s(missing)%s\n' "$C_RED" "$C_RESET" "$hdr" "$C_DIM" "$C_RESET"
      hdr_missing=$((hdr_missing + 1))
    fi
  done
  (( hdr_missing == 0 )) && printf '  %sall common security headers present%s\n' "$C_GREEN" "$C_RESET"

  # --- cookies ------------------------------------------------------------
  local cookies
  cookies=$(printf '%s' "$headers" | grep -i '^set-cookie:' || true)
  if [[ -n "$cookies" ]]; then
    printf '\n%sCookies%s\n' "$C_BOLD" "$C_RESET"
    printf '%s\n' "$cookies" | while IFS= read -r line; do
      local name flag
      name=$(printf '%s' "$line" | sed -E 's/^[Ss]et-[Cc]ookie: *([^=;]*).*/\1/' | cut -d= -f1)
      flag=""
      printf '%s' "$line" | grep -qi 'httponly' && flag="${flag}HttpOnly "
      printf '%s' "$line" | grep -qi 'secure' && flag="${flag}Secure "
      printf '%s' "$line" | grep -qi 'samesite' && flag="${flag}SameSite"
      printf '  %-24s %s\n' "$name" "${flag:-no flags}"
    done
  fi

  # --- TLS ----------------------------------------------------------------
  if have openssl; then
    printf '\n%sTLS certificate%s\n' "$C_BOLD" "$C_RESET"
    if ! tls_summary "$host" 443; then
      printf '  %sunreachable on 443%s\n' "$C_DIM" "$C_RESET"
    fi
  fi

  # --- well known files ---------------------------------------------------
  printf '\n%sWell-known paths%s\n' "$C_BOLD" "$C_RESET"
  local p pcode
  for p in '/robots.txt' '/sitemap.xml' '/.well-known/security.txt' '/favicon.ico'; do
    pcode=$(final_status "${url}${p}" 8)
    if [[ "$pcode" =~ ^[23][0-9][0-9]$ ]]; then
      printf '  %s[+]%s %-26s HTTP %s\n' "$C_GREEN" "$C_RESET" "$p" "$pcode"
    else
      printf '  %s[-]%s %-26s %sHTTP %s%s\n' "$C_DIM" "$C_RESET" "$p" "$C_DIM" "${pcode:-?}" "$C_RESET"
    fi
  done
  return 0
}

# --- Module 6: Info Domain ------------------------------------------------
mod_domain() {
  local target="${1:-}"

  heading "INFO DOMAIN"
  hr 60

  if [[ -z "$target" ]]; then
    target=$(prompt "Domain")
  fi
  target="${target// /}"
  target="${target,,}"

  if [[ -z "$target" ]]; then
    err "no domain given"
    return 1
  fi
  if ! is_hostname "$target"; then
    err "invalid domain: ${target}"
    return 1
  fi

  info "Target: ${C_BOLD}${target}${C_RESET}"

  # --- RDAP ---------------------------------------------------------------
  local rdap ldh registrar status i=0
  rdap=$(rdap_get "domain/${target}") || rdap=''

  if [[ -n "$rdap" ]]; then
    ldh=$(json_get "$rdap" '.ldhName') || ldh=''
    registrar=$(rdap_role_field "$rdap" 'registrar' 'fn') || registrar=''
    if [[ -z "$registrar" ]]; then
      registrar=$(json_get "$rdap" '.entities[0].vcardArray[1][1][3]' || true)
    fi

    printf '\n%sRegistration%s\n' "$C_BOLD" "$C_RESET"
    printf '  Domain        : %s\n' "${ldh:-$target}"
    printf '  Registrar     : %s\n' "${registrar:-unknown}"
    local st
    st=$(json_get "$rdap" '.status[]' 2>/dev/null || true)
    if [[ -n "$st" ]]; then
      printf '  Status        : %s\n' "$(printf '%s' "$st" | tr -d '\r' | awk 'BEGIN{ORS=""} NR>1{printf ", "} {print}')"
    fi

    printf '\n%sEvents%s\n' "$C_BOLD" "$C_RESET"
    while (( i < 6 )); do
      local action date
      action=$(json_get "$rdap" ".events[${i}].eventAction") || action=''
      date=$(json_get "$rdap" ".events[${i}].eventDate") || date=''
      [[ -z "$action" ]] && break
      printf '  %-16s %s\n' "$action" "$date"
      i=$((i + 1))
    done

    printf '\n%sName servers%s\n' "$C_BOLD" "$C_RESET"
    i=0
    while (( i < 12 )); do
      local n
      n=$(json_get "$rdap" ".nameservers[${i}].ldhName") || n=''
      [[ -z "$n" ]] && break
      printf '  %s\n' "$n"
      i=$((i + 1))
    done

    local dnssec
    dnssec=$(json_get "$rdap" '.secureDNS.delegationSigned') || dnssec=''
    printf '\n%sDNSSEC%s\n' "$C_BOLD" "$C_RESET"
    if [[ "$dnssec" == "true" ]]; then
      printf '  Delegation signed : %syes%s\n' "$C_GREEN" "$C_RESET"
    else
      printf '  Delegation signed : %sno / unknown%s\n' "$C_DIM" "$C_RESET"
    fi
    return 0
  fi

  warn "RDAP unavailable, falling back to whois"

  # --- whois fallback -----------------------------------------------------
  if ! have whois; then
    err "neither RDAP nor whois available for this module"
    return 1
  fi
  local out
  out=$(whois "$target" 2>/dev/null || true)
  if [[ -z "$out" ]]; then
    err "whois lookup failed"
    return 1
  fi

  printf '\n%sWhois%s\n' "$C_BOLD" "$C_RESET"
  printf '%s\n' "$out" | grep -iE '^\s*(registrar|registrar name|creation date|created|registry expiry|expiry date|expiration|updated date|last updated|name server|domain status|registrant organization|registrant country|dnssec)' \
    | head -n 30 | while IFS= read -r line; do
      printf '  %s\n' "$(printf '%s' "$line" | sed 's/^[[:space:]]*//')"
    done
  return 0
}

# --- Module 1: My IP ------------------------------------------------------
mod_myip() {
  heading "MY IP"
  hr 60

  local ip='' url
  for url in https://api.ipify.org https://ifconfig.me/ip https://icanhazip.com; do
    ip=$(http_get "$url" 10 1) || ip=''
    if [[ -n "$ip" ]]; then
      break
    fi
  done

  if [[ -z "$ip" ]]; then
    err "could not determine your public IP (all endpoints failed)"
    return 1
  fi

  ok "Public IP: ${C_BOLD}${ip}${C_RESET}"

  local json=''
  json=$(http_get "https://ipwho.is/${ip}" "$HTTP_TIMEOUT" 1) || json=''

  if [[ -n "$json" ]]; then
    local country region city isp asn org tz lat lon
    country=$(json_get "$json" '.country') || country=''
    region=$(json_get "$json" '.region') || region=''
    city=$(json_get "$json" '.city') || city=''
    isp=$(json_get "$json" '.connection.isp') || isp=''
    asn=$(json_get "$json" '.connection.asn') || asn=''
    org=$(json_get "$json" '.connection.org') || org=''
    tz=$(json_get "$json" '.timezone.id') || tz=''
    lat=$(json_get "$json" '.latitude') || lat=''
    lon=$(json_get "$json" '.longitude') || lon=''

    printf '\n%sLocation%s\n' "$C_BOLD" "$C_RESET"
    printf '  Country    : %s\n' "${country:-unknown}"
    printf '  Region     : %s\n' "${region:-unknown}"
    printf '  City       : %s\n' "${city:-unknown}"
    printf '  Coordinates: %s, %s\n' "${lat:-?}" "${lon:-?}"
    printf '  Timezone   : %s\n' "${tz:-unknown}"

    printf '\n%sNetwork%s\n' "$C_BOLD" "$C_RESET"
    printf '  ISP        : %s\n' "${isp:-unknown}"
    printf '  Org        : %s\n' "${org:-unknown}"
    if [[ -n "$asn" ]]; then
      printf '  ASN        : AS%s\n' "$asn"
    fi

    local success
    success=$(json_get "$json" '.success') || success=''
    if [[ "$success" == "false" ]]; then
      local msg
      msg=$(json_get "$json" '.message') || msg=''
      warn "ipwho.is reported: ${msg:-unknown error}"
    fi
  else
    warn "geo enrichment unavailable (ipwho.is unreachable)"
  fi

  # Secondary source: proxy / hosting flags
  local geo2=''
  geo2=$(http_get "http://ip-api.com/json/${ip}?fields=status,country,regionName,city,isp,as,reverse,proxy,hosting,query" "$HTTP_TIMEOUT" 1) || geo2=''
  if [[ -n "$geo2" ]]; then
    local proxy hosting reverse asfull
    proxy=$(json_get "$geo2" '.proxy') || proxy=''
    hosting=$(json_get "$geo2" '.hosting') || hosting=''
    reverse=$(json_get "$geo2" '.reverse') || reverse=''
    asfull=$(json_get "$geo2" '.as') || asfull=''

    printf '\n%sExposure flags%s\n' "$C_BOLD" "$C_RESET"
    [[ "$proxy" == "true" ]] && printf '  %sProxy/VPN detected%s\n' "$C_YELLOW" "$C_RESET" || printf '  Proxy/VPN   : no\n'
    [[ "$hosting" == "true" ]] && printf '  %sHosting provider%s\n' "$C_YELLOW" "$C_RESET" || printf '  Hosting     : no\n'
    printf '  Reverse DNS : %s\n' "${reverse:-n/a}"
    [[ -n "$asfull" ]] && printf '  AS          : %s\n' "$asfull"
  fi
  return 0
}

# --- Module 3: Host DNS Finder --------------------------------------------
mod_dns() {
  local target="${1:-}"

  heading "HOST DNS FINDER"
  hr 60

  if [[ -z "$target" ]]; then
    target=$(prompt "Domain or IP")
  fi
  target="${target// /}"
  target="${target,,}"

  if [[ -z "$target" ]]; then
    err "no target given"
    return 1
  fi
  if ! is_valid_target "$target"; then
    err "invalid target: ${target}"
    return 1
  fi

  info "Target: ${C_BOLD}${target}${C_RESET}"
  hr 60

  if ! have dig && ! have curl; then
    err "dig or curl is required for this module (sudo apt-get install -y dnsutils)"
    return 1
  fi
  if ! have dig; then
    printf '%s[!]%s dig not found, falling back to DNS over HTTPS\n' "$C_YELLOW" "$C_RESET"
  fi

  local rec out line
  local -a records=(A AAAA MX NS TXT CNAME SOA CAA)
  local found_rec=0

  for rec in "${records[@]}"; do
    out=$(dns_query "$target" "$rec" 2>/dev/null || true)
    [[ -z "$out" ]] && continue
    found_rec=1
    printf '\n%s%s records%s\n' "$C_BOLD" "$rec" "$C_RESET"
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      printf '  %s\n' "$line"
    done <<< "$out"
  done

  if (( found_rec == 0 )); then
    printf '\n%sno records found%s\n' "$C_DIM" "$C_RESET"
  fi

  # PTR for IP inputs
  if is_ip "$target"; then
    local rev=''
    if have dig; then
      rev=$(dig +short -x "$target" +time=4 +tries=1 2>/dev/null || true)
    fi
    if [[ -z "$rev" ]] && is_ipv4 "$target"; then
      local rev4
      rev4=$(printf '%s' "$target" | awk -F. '{print $4"."$3"."$2"."$1}')
      rev=$(dns_query "${rev4}.in-addr.arpa" PTR 2>/dev/null || true)
    fi
    printf '\n%sPTR record%s\n' "$C_BOLD" "$C_RESET"
    if [[ -n "$rev" ]]; then
      printf '  %s\n' "$rev"
    else
      printf '  %snone%s\n' "$C_DIM" "$C_RESET"
    fi
  fi

  # DNSSEC / resolver view via DoH
  if have curl; then
    local doh
    doh=$(http_get "https://dns.google/resolve?name=${target}&type=A" "$HTTP_TIMEOUT" 1) || doh=''
    if [[ -n "$doh" ]]; then
      local ad
      ad=$(json_get "$doh" '.AD') || ad=''
      local status
      status=$(json_get "$doh" '.Status') || status=''
      printf '\n%sResolver view%s (dns.google DoH)\n' "$C_BOLD" "$C_RESET"
      printf '  Status code : %s\n' "${status:-?}"
      if [[ "$ad" == "true" ]]; then
        printf '  DNSSEC      : %svalidated (AD flag set)%s\n' "$C_GREEN" "$C_RESET"
      else
        printf '  DNSSEC      : %snot validated%s\n' "$C_DIM" "$C_RESET"
      fi
    fi
  fi
  return 0
}

# ===========================================================================
# MODULE REGISTRY
# ===========================================================================
# cmd <name> <step> <description>
cmd() {
  printf '  %-8s %s(step %s)%s - %s\n' "$1" "$C_DIM" "$2" "$C_RESET" "$3"
}

module_registry() {
  printf '\n%sModules%s\n' "$C_BOLD" "$C_RESET"
  cmd myip 3 "public IP, geo, ISP and ASN"
  cmd info 5 "info IP and site"
  cmd dns 4 "DNS records for a domain"
  cmd scan 16 "port scanner"
  cmd hosts 15 "host finder (IP pivot)"
  cmd domain 6 "domain registration info"
  cmd links 7 "extract links (recursive crawl)"
  cmd subdomains 14 "subdomain finder"
  cmd archive 18 "historical snapshots (wayback)"
  cmd paths 9 "common paths and sensitive files"
  cmd tls 10 "TLS inspector"
  cmd cdn 11 "CDN and WAF detection"
  cmd intel 12 "threat intel and DNSBL"
  cmd secrets 17 "API and secret discovery"
  cmd dorks 19 "search dork generator"
  cmd social 20 "social footprint"
  cmd net 21 "network path"
}

# ===========================================================================
# MENU
# ===========================================================================
show_menu() {
  printf '\n%s%s%s\n' "$C_BOLD" "  RECONNAISSANCE TOOLKIT" "$C_RESET"
  printf '  %sCORE%s\n' "$C_DIM" "$C_RESET"
  printf '  { 1 } My IP\n'
  printf '  { 2 } Info IP and Site\n'
  printf '  { 3 } Host DNS Finder\n'
  printf '  { 4 } Scanner Port\n'
  printf '  { 5 } Host Finder\n'
  printf '  { 6 } Info Domain\n'
  printf '  { 7 } Extract Links\n'
  printf '  { 8 } Subdomain Finder\n'
  printf '  %sRECON EXTRAS%s\n' "$C_DIM" "$C_RESET"
  printf '  { 9 } Historical Snapshots\n'
  printf '  {10 } Common Paths\n'
  printf '  {11 } TLS Inspector\n'
  printf '  {12 } CDN and WAF Detection\n'
  printf '  {13 } Threat Intel\n'
  printf '  {14 } API and Secret Discovery\n'
  printf '  {15 } Search Dork Generator\n'
  printf '  {16 } Social Footprint\n'
  printf '  {17 } Network Path\n'
  printf '\n  { 0 } EXIT\n'
  hr 60
}

menu() {
  local choice=''
  while true; do
    show_menu
    read -r -p "  choice> " choice || choice=''
    case "$choice" in
      1) mod_myip ;;
      3) mod_dns ;;
      2) mod_info ;;
      6) mod_domain ;;
      4) mod_scan ;;
      5) mod_hosts ;;
      7) mod_links ;;
      8) mod_subdomains ;;
      9) mod_archive ;;
      10) mod_paths ;;
      11) mod_tls ;;
      12) mod_cdn ;;
      13) mod_intel ;;
      14) mod_secrets ;;
      15) mod_dorks ;;
      16) mod_social ;;
      17) mod_net ;;
      0) printf '\n%sbye%s\n' "$C_DIM" "$C_RESET"; return 0 ;;
      '') : ;;
      *) warn "invalid option: ${choice}" ;;
    esac
    pause
  done
}

# ===========================================================================
# ENTRY POINT
# ===========================================================================
main() {
  init_colors
  resolve_home || true
  PY="$(detect_python || true)"
  parse_args "$@"

  check_deps || true

  local cmd_name="${ARGS[0]:-}"
  shift || true
  local -a rest=("${ARGS[@]:1}")

  if [[ -z "$cmd_name" ]]; then
    show_banner
    menu
    return 0
  fi

  case "$cmd_name" in
    myip)      mod_myip ;;
    dns)       mod_dns "${rest[0]:-}" ;;
    info)      mod_info "${rest[0]:-}" ;;
    domain)    mod_domain "${rest[0]:-}" ;;
    scan)      mod_scan ${rest[@]+"${rest[@]}"} ;;
    hosts)     mod_hosts ${rest[@]+"${rest[@]}"} ;;
    links)     mod_links ${rest[@]+"${rest[@]}"} ;;
    subdomains) mod_subdomains ${rest[@]+"${rest[@]}"} ;;
    archive)   mod_archive ${rest[@]+"${rest[@]}"} ;;
    paths)     mod_paths ${rest[@]+"${rest[@]}"} ;;
    tls)       mod_tls ${rest[@]+"${rest[@]}"} ;;
    cdn)       mod_cdn ${rest[@]+"${rest[@]}"} ;;
    intel)     mod_intel ${rest[@]+"${rest[@]}"} ;;
    secrets)   mod_secrets ${rest[@]+"${rest[@]}"} ;;
    dorks)     mod_dorks ${rest[@]+"${rest[@]}"} ;;
    social)    mod_social ${rest[@]+"${rest[@]}"} ;;
    net)       mod_net ${rest[@]+"${rest[@]}"} ;;
    modules)   module_registry ;;
    menu)      show_banner; menu ;;
    *)         err "unknown command: ${cmd_name}"; usage; return 1 ;;
  esac
}

main "$@"
