# DIGGER

```
 ____ ___ ____  ____ _____ ____
|  _ \_ _/ ___|/ ___| ____|  _ \
| | | | | |  _| |  _|  _| | |_) |
| |_| | | |_| | |_| | |___|  _ <
|____/___\____|\____|_____|_| \_\
           DIGGER v1.0
passive first - loud when needed
```

A reconnaissance toolkit for Linux. One Bash file, no build step, **keyless
data sources only** — nothing here needs a signup or an API key.

## Install

```bash
git clone <this-repo>
cd digger
chmod +x digger.sh
./digger.sh
```

Dependencies (Debian/Ubuntu):

```bash
sudo apt-get install -y curl dnsutils nmap whois jq openssl iputils-ping traceroute mtr-tiny
```

`jq` is used for JSON when present; `python3` is used as a fallback, so
neither is fatal. `nmap`, `ping`, `traceroute` and `mtr` are only needed by
the modules that use them.

## Usage

```bash
./digger.sh              # interactive menu
./digger.sh myip         # single module, non-interactive
./digger.sh dns example.com
./digger.sh --help
```

In the menu, type the number of the module you want and press enter. `0`
exits.

### Options

| Flag | Effect |
|---|---|
| `-h`, `--help` | usage |
| `--version` | version |
| `--no-color` | disable ANSI colours |
| `--no-banner` | suppress the banner |
| `--timeout <sec>` | per-request HTTP timeout (default 15) |
| `-y`, `--yes` | skip confirmation prompts |

### Environment

| Variable | Effect |
|---|---|
| `NO_COLOR=1` | disable colours (standard) |
| `ASSUME_YES=1` | skip confirmation prompts |
| `HTTP_TIMEOUT=15` | per-request timeout in seconds |

## Modules

| # | Module | Command | Status |
|---|--------|---------|--------|
| 1 | My IP | `myip` | done |
| 2 | Info IP and Site | `info` | planned |
| 3 | Host DNS Finder | `dns` | done |
| 4 | Scanner Port | `scan` | planned |
| 5 | Host Finder (IP pivot) | `hosts` | planned |
| 6 | Info Domain | `domain` | planned |
| 7 | Extract Links (recursive crawl) | `links` | planned |
| 8 | Subdomain Finder | `subdomains` | planned |
| 9 | Historical Snapshots (Wayback) | `archive` | planned |
| 10 | Common Paths / Sensitive Files | `paths` | planned |
| 11 | TLS Inspector | `tls` | planned |
| 12 | CDN and WAF Detection | `cdn` | planned |
| 13 | Threat Intel (DNSBL) | `intel` | planned |
| 14 | API and Secret Discovery | `secrets` | planned |
| 15 | Search Dork Generator | `dorks` | planned |
| 16 | Social Footprint | `social` | planned |
| 17 | Network Path | `net` | planned |

## Data sources

All keyless, all verified reachable:

- `api.ipify.org`, `ifconfig.me`, `icanhazip.com` — public IP
- `ipwho.is`, `ip-api.com` — geolocation and exposure flags
- `rdap.org` — registration and netblock data (IP and domain)
- `dns.google` — DNS over HTTPS
- `crt.sh`, `api.certspotter.com` — certificate transparency
- `api.hackertarget.com` — passive DNS and reverse IP
- `web.archive.org` — historical snapshots
- `blocklist.de`, `cinsscore.com`, `check.torproject.org`, `openphish.com` — threat intel

URLhaus is deliberately excluded: its API now requires an auth key and its
download feeds return HTTP 410.

## Tests

```bash
bash tests/smoke.sh
```

The suite runs every module in CLI mode against live targets and fails on
any non-zero exit or missing expected output. It grows as modules land.

## Scope

DIGGER performs reconnaissance against targets you choose. Use it on
systems you own or have written permission to assess. Active probing
(port scan, path probing, secret scanning) asks for confirmation before it
runs.

## Licence

MIT — see [LICENSE](LICENSE).
