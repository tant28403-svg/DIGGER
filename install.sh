#!/usr/bin/env bash
#
# DIGGER installer - puts a `digger` command in your PATH.
#
#   ./install.sh                  symlink into ~/.local/bin
#   ./install.sh --copy           copy instead of symlink
#   ./install.sh --prefix /usr/local/bin
#   ./install.sh --uninstall
#
# Nothing is downloaded and nothing leaves this directory except the link.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${ROOT}/digger.sh"
PREFIX="${HOME}/.local/bin"
MODE='link'
ACTION='install'

if [[ -t 1 ]]; then
  B=$'\033[1m'; G=$'\033[32m'; Y=$'\033[33m'; D=$'\033[2m'; N=$'\033[0m'
else
  B=''; G=''; Y=''; D=''; N=''
fi

usage() {
  cat <<EOF
${B}DIGGER installer${N}

  ./install.sh [options]

${B}OPTIONS${N}
  --prefix DIR    install into DIR (default: ~/.local/bin)
  --copy          copy the script instead of symlinking it
  --uninstall     remove the installed command
  -h, --help      this help
EOF
}

while (( $# > 0 )); do
  case "$1" in
    --prefix)    PREFIX="${2:-}"; shift 2 || shift ;;
    --copy)      MODE='copy'; shift ;;
    --uninstall) ACTION='uninstall'; shift ;;
    -h|--help)   usage; exit 0 ;;
    *)           printf 'unknown option: %s\n\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ -z "$PREFIX" ]]; then
  printf 'error: --prefix needs a directory\n' >&2
  exit 2
fi
TARGET="${PREFIX}/digger"

if [[ "$ACTION" == 'uninstall' ]]; then
  if [[ -e "$TARGET" || -L "$TARGET" ]]; then
    rm -f "$TARGET"
    printf '%sremoved%s %s\n' "$G" "$N" "$TARGET"
  else
    printf 'nothing to remove at %s\n' "$TARGET"
  fi
  exit 0
fi

# --- checks ----------------------------------------------------------------
if [[ ! -f "$SRC" ]]; then
  printf 'error: digger.sh not found next to install.sh\n' >&2
  exit 1
fi

bash_major="${BASH_VERSINFO[0]}"
bash_minor="${BASH_VERSINFO[1]}"
if (( bash_major < 4 || (bash_major == 4 && bash_minor < 3) )); then
  printf 'error: bash 4.3 or newer is required (found %s.%s)\n' \
    "$bash_major" "$bash_minor" >&2
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  printf 'error: curl is required (every module talks HTTP)\n' >&2
  exit 1
fi

printf '%sDIGGER%s %sinstaller%s\n' "$B" "$N" "$D" "$N"
printf '  source      : %s\n' "$SRC"
printf '  destination : %s %s(%s)%s\n' "$TARGET" "$D" "$MODE" "$N"

if command -v jq >/dev/null 2>&1; then
  printf '  json        : jq\n'
elif command -v python3 >/dev/null 2>&1; then
  printf '  json        : python3 %s(jq not found)%s\n' "$D" "$N"
else
  printf '  json        : %smissing jq and python3, json sources will fail%s\n' "$Y" "$N"
fi

optional=''
for tool in dig nmap openssl whois traceroute mtr ping; do
  command -v "$tool" >/dev/null 2>&1 && optional="${optional} ${tool}"
done
printf '  optional    :%s\n' "${optional:- none found}"

# --- install ---------------------------------------------------------------
mkdir -p "$PREFIX"
if [[ "$MODE" == 'link' ]]; then
  ln -sfn "$SRC" "$TARGET"
else
  cp "$SRC" "$TARGET"
fi
chmod +x "$SRC" "$TARGET"

printf '\n%sdone%s - run it with: %sdigger%s\n' "$G" "$N" "$B" "$N"
case ":${PATH}:" in
  *":${PREFIX}:"*) ;;
  *) printf '%snote%s %s is not in your PATH yet:\n' "$Y" "$N" "$PREFIX"
     printf '  export PATH="%s:$PATH"\n' "$PREFIX" ;;
esac
