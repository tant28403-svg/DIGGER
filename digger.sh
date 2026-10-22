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

WORKDIR=""
DIGGER_HOME=""
cleanup() {
  if [[ -n "$WORKDIR" && -d "$WORKDIR" ]]; then
    rm -rf "$WORKDIR"
  fi
  return 0
}
trap cleanup EXIT INT TERM

# Locate the directory holding digger.sh so shipped wordlists are found no
# matter what the current working directory is.
resolve_home() {
  local src="${BASH_SOURCE[0]}" dir
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
    C_BLUE=$'\033[34m'
    C_CYAN=$'\033[36m'
  else
    C_RESET=''; C_BOLD=''; C_DIM=''
    C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''; C_CYAN=''
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
  dns <domain|ip>            DNS records for a domain (A AAAA MX NS TXT CNAME SOA CAA)
  info <ip|host>             deep dive on an IP address or a website
  domain <domain>            registration data for a domain
  links <url>                crawl a site and list every link it finds
  paths <url>                probe common paths and sensitive files

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
  curl dig jq (or python3) openssl nmap whois
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
      -- "$url" 2>/dev/null)
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
      -- "$url" 2>/dev/null)
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
path = sys.argv[1]
iterate = path.endswith('[]')
if iterate:
    path = path[:-2]
cur = data
for m in re.finditer(r'\.([A-Za-z0-9_-]+)|\[(\d+)\]', path):
    key, idx = m.group(1), m.group(2)
    try:
        if key is not None:
            cur = cur.get(key) if isinstance(cur, dict) else None
        else:
            cur = cur[int(idx)] if isinstance(cur, list) else None
    except Exception:
        cur = None
    if cur is None:
        break
if cur is None:
    sys.exit(1)
if iterate:
    if not isinstance(cur, list):
        sys.exit(1)
    for item in cur:
        if isinstance(item, bool):
            print('true' if item else 'false')
        elif isinstance(item, (dict, list)):
            print(json.dumps(item))
        elif item is None:
            print('null')
        else:
            print(item)
    sys.exit(0)
if isinstance(cur, bool):
    print('true' if cur else 'false')
elif isinstance(cur, (dict, list)):
    print(json.dumps(cur))
elif cur is None:
    print('null')
else:
    print(cur)
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
      ip=$(json_get "$json" '.Answer[0].data') || ip=''
    fi
  fi
  [[ -n "$ip" ]] || return 1
  printf '%s' "$ip"
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
  local base="$1" href="$2" out=''
  href="${href%%#*}"
  [[ -z "$href" ]] && return 1
  if [[ -n "$PY" ]]; then
    out=$("$PY" -c 'import sys,urllib.parse;print(urllib.parse.urljoin(sys.argv[1],sys.argv[2]))' \
      "$base" "$href" 2>/dev/null || true)
    if [[ -n "$out" ]]; then
      printf '%s' "$out"
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
  local top base_code='' base_size='' base_hits=0
  top=$(printf '%s\n' "$raw" | awk -F'\t' 'NF>=2{print $1" "$2}' | sort | uniq -c | sort -rn | head -n1 || true)
  if [[ -n "$top" ]]; then
    base_hits=$(printf '%s' "$top" | awk '{print $1}')
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

# --- Module 2: Info IP and Site -------------------------------------------
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
  local port scheme code found=0
  for port in 80 443 8080 8443; do
    scheme="http"
    [[ "$port" == "443" || "$port" == "8443" ]] && scheme="https"
    code=$(final_status "${scheme}://${ip}:${port}" 6)
    if [[ "$code" =~ ^[1-5][0-9][0-9]$ ]] && [[ "$code" != "000" ]]; then
      printf '  %-6s %s -> HTTP %s\n' "$port" "$scheme" "$code"
      found=1
    fi
  done
  (( found )) || printf '  %sno web service on common ports%s\n' "$C_DIM" "$C_RESET"
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
  local h present missing=0
  for h in 'Strict-Transport-Security' 'Content-Security-Policy' 'X-Frame-Options' \
           'X-Content-Type-Options' 'Referrer-Policy' 'Permissions-Policy'; do
    if header_present "$headers" "$h"; then
      printf '  %s[+]%s %s\n' "$C_GREEN" "$C_RESET" "$h"
    else
      printf '  %s[-]%s %s %s(missing)%s\n' "$C_RED" "$C_RESET" "$h" "$C_DIM" "$C_RESET"
      missing=$((missing + 1))
    fi
  done
  (( missing == 0 )) && printf '  %sall common security headers present%s\n' "$C_GREEN" "$C_RESET"

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
  local rdap ldh registrar status events ns i=0
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

  if ! have dig; then
    err "dig is required for this module (sudo apt-get install -y dnsutils)"
    return 1
  fi

  local rec out
  local -a records=(A AAAA MX NS TXT CNAME SOA CAA)

  for rec in "${records[@]}"; do
    out=$(dig +noall +answer +time=4 +tries=1 "$target" "$rec" 2>/dev/null || true)
    if [[ -z "$out" ]]; then
      continue
    fi
    printf '\n%s%s records%s\n' "$C_BOLD" "$rec" "$C_RESET"
    printf '%s\n' "$out" | awk -v c="$C_DIM" -v r="$C_RESET" '{
      name=$1; ttl=$2; type=$4; data="";
      for (i=5; i<=NF; i++) data = data (i>5 ? " " : "") $i;
      printf "  %-40s %-8s %s\n", name, ttl, data;
    }'
  done

  # PTR for IP inputs
  if is_ip "$target"; then
    local rev
    rev=$(dig +short -x "$target" +time=4 +tries=1 2>/dev/null || true)
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
  cmd dns 4 "DNS records for a domain"
  cmd info 5 "info IP and site"
  cmd domain 6 "domain registration info"
  cmd links 7 "extract links (recursive crawl)"
  cmd paths 9 "common paths and sensitive files"
  cmd tls 10 "TLS inspector"
  cmd cdn 11 "CDN and WAF detection"
  cmd intel 12 "threat intel and DNSBL"
  cmd subdomains 14 "subdomain finder"
  cmd hosts 15 "host finder (IP pivot)"
  cmd scan 16 "port scanner"
  cmd secrets 17 "API and secret discovery"
  cmd dorks 18 "search dork generator"
  cmd social 19 "social footprint"
  cmd net 20 "network path"
}
pending() {
  local name="$1" step="$2"
  warn "module '${name}' is not implemented yet (planned for build step ${step})"
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
      4) pending "scan" 16 ;;
      5) pending "hosts" 15 ;;
      7) mod_links ;;
      8) pending "subdomains" 14 ;;
      9) pending "archive" 9 ;;
      10) mod_paths ;;
      11) mod_tls ;;
      12) pending "cdn" 11 ;;
      13) pending "intel" 12 ;;
      14) pending "secrets" 17 ;;
      15) pending "dorks" 18 ;;
      16) pending "social" 19 ;;
      17) pending "net" 20 ;;
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

  if [[ ! -d "$WORKDIR" ]]; then
    WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/digger.XXXXXX")
  fi

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
    scan)      pending "scan" 16 ;;
    hosts)     pending "hosts" 15 ;;
    links)     mod_links ${rest[@]+"${rest[@]}"} ;;
    subdomains) pending "subdomains" 14 ;;
    archive)   pending "archive" 9 ;;
    paths)     mod_paths ${rest[@]+"${rest[@]}"} ;;
    tls)       mod_tls ${rest[@]+"${rest[@]}"} ;;
    cdn)       pending "cdn" 11 ;;
    intel)     pending "intel" 12 ;;
    secrets)   pending "secrets" 17 ;;
    dorks)     pending "dorks" 18 ;;
    social)    pending "social" 19 ;;
    net)       pending "net" 20 ;;
    modules)   module_registry ;;
    menu)      show_banner; menu ;;
    *)         err "unknown command: ${cmd_name}"; usage; return 1 ;;
  esac
}

main "$@"
