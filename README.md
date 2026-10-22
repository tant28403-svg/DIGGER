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
data sources only** — nothing here needs a signup, a token or an API key.

Seventeen modules, an interactive menu, and the same seventeen as CLI
subcommands for scripting.

## Install

```bash
git clone https://github.com/tant28403-svg/DIGGER.git digger
cd digger
./install.sh              # symlink into ~/.local/bin
digger                    # menu
```

No install step required if you prefer to run it in place:

```bash
chmod +x digger.sh
./digger.sh
```

### Dependencies

| Need | Why | If missing |
|---|---|---|
| `bash` 4.3+ | arrays, `mapfile`, case conversion | required |
| `curl` | every HTTP module | required |
| `jq` **or** `python3` | JSON parsing | required, one of them |
| `dig` | DNS records, rapid resolution | falls back to DNS over HTTPS |
| `openssl` | TLS inspector | module reports it is unavailable |
| `nmap` | port scanner | built-in `/dev/tcp` scanner |
| `traceroute` / `mtr` / `ping` | network path | tries all three, warns if none |
| `whois` | domain fallback | RDAP is used anyway |

Debian/Ubuntu:

```bash
sudo apt-get install -y curl jq dnsutils nmap openssl whois iputils-ping traceroute mtr-tiny
```

Nothing needs root. The port scanner uses `nmap -sT` (a plain TCP connect), so
it runs as your normal user.

## Usage

```bash
./digger.sh                   # interactive menu
./digger.sh myip              # one module, non-interactive
./digger.sh dns example.com
./digger.sh --help
```

In the menu, type the module number and press enter. `0` exits. Modules that
send packets to the target ask before they start; the flag `-y` answers yes.

### Options

| Flag | Effect |
|---|---|
| `-h`, `--help` | usage |
| `--version` | version |
| `--no-color` | disable ANSI colours |
| `--no-banner` | suppress the banner |
| `--timeout <sec>` | per-request HTTP timeout (default 15) |
| `-y`, `--yes` | skip confirmation prompts |

| Variable | Effect |
|---|---|
| `NO_COLOR=1` | disable colours (standard) |
| `ASSUME_YES=1` | skip confirmation prompts |
| `HTTP_TIMEOUT=15` | per-request timeout in seconds |

## Modules

| # | Module | Command | What it gives you |
|---|--------|---------|-------------------|
| 1 | My IP | `myip` | public IP, geo, ISP, ASN, proxy/hosting flags |
| 2 | Info IP and Site | `info` | netblock, PTR, geo, headers and registration in one pass |
| 3 | Host DNS Finder | `dns` | A, AAAA, MX, NS, TXT, CNAME, SOA, CAA, SRV |
| 4 | Scanner Port | `scan` | TCP ports and banners (`nmap -sT`, or `/dev/tcp`) |
| 5 | Host Finder | `hosts` | forward/reverse names, passive DNS, optional vhost probing |
| 6 | Info Domain | `domain` | registrar, dates, status, nameservers via RDAP |
| 7 | Extract Links | `links` | every link on a site, internal and external, deduplicated |
| 8 | Subdomain Finder | `subdomains` | CT logs + passive DNS + wordlist + patterns, scored |
| 9 | Historical Snapshots | `archive` | Wayback coverage, per-year timeline, recent captures |
| 10 | Common Paths | `paths` | 206 common and sensitive paths, soft-404 aware |
| 11 | TLS Inspector | `tls` | certificate chain, protocols, ciphers, key sizes |
| 12 | CDN and WAF | `cdn` | edge provider and WAF from headers, CNAMEs, issuer, ASN |
| 13 | Threat Intel | `intel` | DNSBL, blocklist.de, cinsscore, Tor exit list, OpenPhish |
| 14 | API and Secret | `secrets` | crawls pages and JS, flags 27 key and token patterns |
| 15 | Search Dork | `dorks` | 42 engine queries in 7 categories, offline |
| 16 | Social Footprint | `social` | a handle across 20 platforms, plus domain-derived handles |
| 17 | Network Path | `net` | traceroute with ASN, prefix and organisation per hop |

Active modules — port scan, path probing, secret scanning, vhost probing and
traceroute — ask first and accept `-y` for unattended runs.

### Examples

```bash
./digger.sh myip
./digger.sh info 8.8.8.8
./digger.sh info https://example.com
./digger.sh dns example.com
./digger.sh scan example.com --ports 22,80,443,8000-8100 -y
./digger.sh hosts 93.184.216.34
./digger.sh hosts example.com --vhosts -y
./digger.sh domain example.com
./digger.sh links https://example.com --depth 2
./digger.sh subdomains example.com --limit 500
./digger.sh archive example.com --year 2015
./digger.sh paths https://example.com -y
./digger.sh tls example.com:443
./digger.sh cdn example.com
./digger.sh intel 1.2.3.4
./digger.sh secrets https://example.com -y
./digger.sh dorks example.com --category config --links
./digger.sh social torvalds
./digger.sh net 8.8.8.8
```

Each module prints its own options with `--help`:

```bash
./digger.sh subdomains --help
```

## Data sources

Every source is public and keyless:

- `api.ipify.org`, `ifconfig.me`, `icanhazip.com` — your public IP
- `ipwho.is`, `ip-api.com` — geolocation, ISP, ASN, exposure flags
- `rdap.org` — registration data for domains and IP netblocks
- `dns.google` — DNS over HTTPS; the universal fallback when `dig` is absent
- `crt.sh`, `api.certspotter.com` — certificate transparency
- `api.subdomain.center`, `api.mnemonic.no`, `api.hackertarget.com` — passive DNS
- `web.archive.org` (CDX + availability) — historical snapshots
- `blocklist.de`, `cinsscore.com`, `check.torproject.org`, `openphish.com` — threat intel
- `origin.asn.cymru.com`, `asn.cymru.com` — ASN and network labels for the path

URLhaus is deliberately excluded: its API now requires a key and its download
feeds answer with HTTP 410.

Free endpoints rate limit. When a source answers 429 or 502 the module says so
and moves on instead of pretending the target does not exist.

## Wordlists

`wordlist/subdomains.txt` (803 labels) and `wordlist/paths.txt` (206 paths)
ship with the tool. If SecLists is installed, the subdomain finder also reads
`/usr/share/seclists/Discovery/DNS/subdomains-top1million-20000.txt` when it
is present.

## Output and safety

- Everything is printed to the terminal; no report files, no cache on disk.
- Passive modules run immediately. Active ones (packets to the target) print
  what they will do and wait for a `y`.
- Non-interactive runs (`cron`, CI, pipes) skip the prompt and refuse unless
  `-y` was given. They never hang waiting for input.

## Scope

DIGGER performs reconnaissance against targets you choose. Use it on systems
you own or have written permission to assess. Active probing — port scanning,
path probing, secret scanning, vhost probing and traceroute — asks for
confirmation before it runs.

## Licence

MIT — see [LICENSE](LICENSE).
