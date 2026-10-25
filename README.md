# DIGGER

```
 ____ ___ ____  ____ _____ ____
|  _ \_ _/ ___|/ ___| ____|  _ \
| | | | | |  _| |  _|  _| | |_) |
| |_| | | |_| | |_| | |___|  _ <
|____/___\____|\____|_____|_| \_\
           DIGGER v2.0
passive first - loud when needed
```

A reconnaissance toolkit for Linux. One Bash file, no build step, **keyless
data sources only** — nothing here needs a signup, a token or an API key.

Seventeen modules, an interactive menu, and the same seventeen as CLI
subcommands for scripting.

## Important

Please read this whole README before running the tool. It explains the
required setup, the difference between passive and active modules, which
optional tools unlock which features, and a few things that commonly cause
confusion — for example rate limits from free services, missing binaries, and
the fact that "not found" in the output does not prove that something does not
exist. Taking a couple of minutes to read it will save you guesswork.

**Open Source Notice:** This project is open source. `digger.sh` is a single
readable Bash file: every module, endpoint and threshold is visible in the
source. There are no hidden services, no telemetry and no credentials
embedded in the tool. Anyone who clones this repository can read and
understand the complete implementation. Please use it responsibly, and only
against systems you own or have explicit written permission to test.

**Capability Notice:** This is a passive-first reconnaissance toolkit for
authorised assessment and learning. It is not an exploitation framework.

**v2.0 Performance layer (enabled by default):** connection reuse (keepalive,
HTTP/2), in-memory DNS and passive-source caching, shared bounded concurrency
with adaptive backoff, and exponential retries — all transparent to existing
workflows.

**Optional stealth/evasion mode (opt-in, requires `--i-have-permission`):**
proxy rotation, User-Agent rotation, randomised delays/jitter, request ordering
randomisation, adaptive backoff, and audit logging. Address spoofing is not
supported. All features send ordinary DNS, HTTP, TLS, TCP or traceroute
traffic to the target you choose. Third-party data can be incomplete, stale
or rate-limited, and a finding is a lead to verify — not proof of a
vulnerability.

⚠️ **FOR EDUCATIONAL USE AND AUTHORISED SECURITY TESTING ONLY**
Please use this tool only against systems you own or have explicit written
permission to test. Unauthorised testing is illegal in most jurisdictions.

⚠️ **The author cannot be held responsible for any misuse.**

DIGGER is a reconnaissance toolkit for authorised testing: it collects public
information about a target you choose, and it contacts that target only when
you run an active module.

## Download

Bash 4.3 or later and `curl` are required. Linux is the supported platform.

Windows support: DIGGER is a Bash tool and is not natively supported on
Windows. Please use WSL, which is the closest match to the intended
environment. It also runs under Git Bash, but optional tools such as `dig`,
`nmap` and `traceroute` are usually missing there, so several modules will use
their fallbacks or report that a tool is unavailable.

```bash
git clone https://github.com/tant28403-svg/DIGGER.git digger
cd digger
./install.sh              # symlink into ~/.local/bin
digger                    # menu
```

No install step is required if you prefer to run it in place:

```bash
chmod +x digger.sh
./digger.sh
```

The installer does not download anything. It checks the basics, then symlinks
(or copies) `digger.sh` into `~/.local/bin` by default, or into the directory
you choose, and tells you if that directory is not on your `PATH`:

```bash
./install.sh                  # symlink into ~/.local/bin
./install.sh --copy           # copy the script instead of symlinking
./install.sh --prefix /usr/local/bin
./install.sh --uninstall
```

`--copy` copies only `digger.sh`, and some Windows filesystems turn a symlink
into a copy. If either applies, keep the `wordlist/` directory next to the
copy, or under `~/.local/share/digger/`, otherwise the paths module has no
list to probe.

### Dependencies

| Need | Why | If missing |
|---|---|---|
| `bash` 4.3+ | arrays, `mapfile`, case conversion | the tool assumes it; the installer refuses older shells |
| `curl` | every HTTP module | required; the tool reports it at startup |
| `jq` **or** `python3` | JSON parsing | strongly recommended; without either, JSON-based lookups fail |
| `dig` | DNS records and faster subdomain resolution | DNS over HTTPS is used instead; brute-force budget drops from 1500 to 150 names |
| `nmap` | full port scan and version detection | a built-in `/dev/tcp` scanner checks 62 common ports |
| `openssl` | TLS inspector and the TLS part of `info` | the `tls` module reports it is unavailable; the TLS summary in `info` is skipped |
| `whois` | fallback when RDAP fails | RDAP is used on its own |
| `traceroute`, `mtr` or `ping` | network path | the module tries all three and warns if none is usable |

Debian/Ubuntu:

```bash
sudo apt-get install -y curl jq dnsutils nmap openssl whois iputils-ping traceroute mtr-tiny
```

DIGGER itself needs no root. The port scanner uses `nmap -sT` (a plain TCP
connect) and the fallback uses Bash's `/dev/tcp`, so scanning works as your
normal user.

## Use

There is nothing to configure — clone the repository and you are ready to run.

```bash
./digger.sh                   # interactive menu
./digger.sh --help            # every command and global option
./digger.sh myip              # one module, non-interactive
```

In the menu, type the module number and press enter. The numbering is fixed:
modules 1–8 are the core set, 9–17 are the extras, and `0` exits.

| # | Module | Command | What it gives you |
|---|--------|---------|-------------------|
| 1 | My IP | `myip` | your public IP, location, ISP, ASN and exposure flags |
| 2 | Info IP and Site | `info` | IP: geo, ASN, netblock, PTR, co-hosted names, web ports. Site: headers, title, technology, security headers, cookies, TLS summary, well-known paths |
| 3 | Host DNS Finder | `dns` | A, AAAA, MX, NS, TXT, CNAME, SOA, CAA; PTR when given an IP |
| 4 | Scanner Port | `scan` | TCP ports and service names (`nmap -sT`, or a `/dev/tcp` fallback) |
| 5 | Host Finder | `hosts` | forward and reverse names, passive DNS, optional vhost probing |
| 6 | Info Domain | `domain` | registrar, important dates, status and nameservers via RDAP |
| 7 | Extract Links | `links` | links found while crawling, internal and external, deduplicated |
| 8 | Subdomain Finder | `subdomains` | certificate transparency, passive DNS, a wordlist and patterns, scored by confidence |
| 9 | Historical Snapshots | `archive` | Wayback coverage, a per-year timeline and recent captures |
| 10 | Common Paths | `paths` | 206 common and sensitive paths, with a soft-404 baseline |
| 11 | TLS Inspector | `tls` | certificate details, chain, protocol versions and cipher per version |
| 12 | CDN and WAF Detection | `cdn` | edge provider and WAF from headers, CNAMEs, certificate issuer and ASN |
| 13 | Threat Intel | `intel` | DNS blacklists, blocklist.de, cinsscore, the Tor exit list and OpenPhish |
| 14 | API and Secret Discovery | `secrets` | crawls pages and scripts, flags 27 key and token patterns |
| 15 | Search Dork Generator | `dorks` | 42 search queries in 7 categories, generated offline |
| 16 | Social Footprint | `social` | a handle across 20 platforms, plus handles derived from a domain |
| 17 | Network Path | `net` | traceroute with ASN, prefix and organisation per hop |
| 0 | Exit | — | leave the menu |

### Passive and active modules

Most of the data DIGGER shows comes from public services. A few modules talk
to the target itself, and those are the ones to think about before running
them.

| Module | Contacts the target? |
|---|---|
| `myip` | No; it asks public IP services about your own address |
| `info` | Yes; it fetches the site, or probes common web ports on an IP |
| `dns` | No; DNS queries only |
| `scan` | Yes; TCP connect scan |
| `hosts` | No by default; yes with `--vhosts` |
| `domain` | No; RDAP, with a `whois` fallback |
| `links` | Yes; HTTP crawl |
| `subdomains` | No direct requests; names are resolved through DNS |
| `archive` | No; Wayback Machine only |
| `paths` | Yes; HTTP probes to the target |
| `tls` | Yes; TLS handshakes |
| `cdn` | Yes; HTTP and TLS to the target |
| `intel` | No direct requests; third-party lists and DNS resolution |
| `secrets` | Yes; HTTP crawl of pages and scripts |
| `dorks` | No; queries are generated offline |
| `social` | No direct requests to the target; public platforms are queried |
| `net` | Yes; traceroute probes |

Five modules ask for confirmation before they send their traffic: `scan`,
`paths`, `secrets`, `hosts --vhosts` and `net`. Answer `y` to continue; the
default is No. The flag `-y` (or `ASSUME_YES=1`) answers yes for unattended
runs. The remaining active modules (`info`, `links`, `tls`, `cdn`) run without
a prompt.

If standard input is not a terminal — a cron job, a pipe, CI — the
confirmation prompt is skipped and the active part is refused unless `-y` was
given. It does not block waiting for a terminal answer. The interactive menu
itself expects a terminal; scripts should call a module subcommand instead.

### Examples

```bash
./digger.sh myip
./digger.sh info 8.8.8.8
./digger.sh info example.com
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

Modules that take options print their own usage with `--help`:

```bash
./digger.sh subdomains --help
```

## Notes on the modules

These are the details that are easy to misunderstand. They are worth a quick
read before you interpret the output.

- **My IP** tries `api.ipify.org`, `ifconfig.me` and `icanhazip.com` in order.
  Location and network data come from `ipwho.is`; the proxy/VPN and hosting
  flags come from `ip-api.com` over plain HTTP, so they only appear when that
  second source answers. If the flags are missing, the second source did not
  answer; the rest of the output is still valid.
- **Info IP and Site** accepts an IP address or a bare hostname (not a URL).
  For an IP it looks up the netblock, PTR record, co-hosted names and a quick
  HTTP check of ports 80, 443, 8080 and 8443. For a site it resolves the host,
  follows redirects, reads the headers, title and technology hints, audits six
  common security headers, lists cookie flags, prints a certificate summary
  (when `openssl` is present) and checks `robots.txt`, `sitemap.xml`,
  `security.txt` and `favicon.ico`. Use `domain` if you want registration data
  for a site.
- **Host DNS Finder** covers A, AAAA, MX, NS, TXT, CNAME, SOA and CAA, plus
  PTR when the input is an address. It does not query SRV, DS or DNSSEC
  records. If `dig` is not installed, the queries go through DNS over HTTPS.
- **Scanner Port** uses `nmap -sT -Pn -n -T4` on the top 1000 ports by default;
  `--fast` narrows that to the top 100 and `--ports` takes an nmap port
  specification. `--version` adds service/version detection, and needs nmap.
  Without nmap, a Bash `/dev/tcp` scanner checks a built-in list of 63 common
  ports and reports that it could not do version detection. Ports that are
  filtered or closed may simply not answer; that is not the same as "nothing
  is there".
- **Host Finder** shows forward A/AAAA/CNAME records, the PTR record, and
  names seen in passive DNS sources. Names are sorted and the display stops
  after 40. `--vhosts` sends Host-header probes to candidates taken from the
  passive names and, when the input is a domain, the shipped subdomain
  wordlist, with a random-name baseline to filter soft-404 pages. It probes at
  most 100 names by default (`--limit` changes that) and asks before starting.
- **Info Domain** asks RDAP first. If RDAP is unavailable it falls back to
  `whois`; if neither is available, the module says so instead of inventing an
  answer.
- **Extract Links** crawls breadth-first: depth 5, at most 100 pages, 0.3s
  between requests. It reads `robots.txt` and stays out of disallowed paths
  unless `--ignore-robots` is given. External links are always listed, but
  they are only crawled when `--include-external` is set.
- **Subdomain Finder** combines five keyless sources — crt.sh,
  certspotter, subdomain.center, mnemonic.no and hackertarget — with the
  shipped 803-label wordlist and a pattern generator covering 85 core labels
  and 6 environment words. Names are resolved with `dig` when available, or
  with DNS over HTTPS when it is not, and a sample of up to 25 names is
  confirmed against a second resolver.
  Confidence is deliberately simple:
  high = resolves now **and** appears in certificate transparency or passive
  DNS; medium = resolves now but only came from the wordlist or pattern
  generator; low = appears in a passive source but does not resolve right
  now. A wildcard DNS record is detected and reported, so you can judge the
  results yourself.

  One practical detail: without `dig`, the brute-force part of the run is
  limited to 150 names by default (1500 with `dig`) so the module finishes in
  a reasonable time. Passive names are always checked, and `--limit` raises
  the brute-force budget. Brute-force candidates that do not resolve and were
  never seen in a passive source are not printed, so a short list does not
  mean those names are free.
- **Historical Snapshots** reads the Wayback CDX index, prints coverage, a
  per-year count and the most recent captures (10 by default), and accepts
  date and status-code filters. The availability endpoint is only queried
  when no time filter is set. An empty result can mean the site was never
  archived, or that the index is temporarily rate-limited.
- **Common Paths** probes the shipped 206-path wordlist. It builds a
  soft-404 baseline from the most common status/size pair and groups results
  as Found, Interesting (401/403/405), soft-404 baseline, or other responses.
  To keep the output readable, it shows at most 30 entries per group; the
  counts above each group are the full numbers. `--wordlist` accepts your own
  list and `--no-follow` stops redirects from being followed.
- **TLS Inspector** needs `openssl`. It reports the negotiated protocol and
  cipher, chain length, certificate subject, issuer, validity dates, SANs,
  the SHA-256 fingerprint and key details, then tests TLS 1.0, 1.1, 1.2 and 1.3
  individually. Findings include expiry, wildcard certificates, weak
  signatures, small keys and hostname coverage. Self-signed or mismatched
  certificates are common and are not treated as an error.
- **CDN and WAF** only reports a provider as detected when a response header,
  CNAME or certificate issuer matches. An ASN match on its own is marked
  "possible", because many unrelated sites share the same network.
- **Threat Intel** resolves a domain to an address first, then checks six DNS
  blacklists, blocklist.de, cinsscore, the Tor exit list and the OpenPhish
  feed. Free lists are refreshed on their own schedules and a listing on a
  shared IP says little about a particular site; treat a hit as a reason to
  look further, not as a verdict.
- **API and Secret** crawls up to 10 pages and 25 linked scripts at depth 2,
  with a 0.2s delay, and matches 27 high/medium/low-confidence patterns
  against the text. Each result shows the pattern name, a masked value and
  the page it came from. It does not contact the credential providers and
  does not validate keys, so public identifiers and example strings can
  produce false positives.
- **Search Dork** generates 42 queries in 7 categories (files, config, panels,
  leaks, errors, docs, hosts) for Google, Bing, DuckDuckGo or Brave. Nothing
  is sent: with `--links` it only turns each query into a ready-to-open URL.
- **Social Footprint** checks 20 public platforms and classifies the responses
  as found, not found or unknown. Hacker News and Steam are checked with a
  text marker because they answer 200 for missing users; platforms that
  block automated requests may come back as unknown. A "not found" is not
  proof that the handle is unused everywhere.
- **Network Path** uses `traceroute`, then `mtr` (UDP mode), then a
  TTL-walking `ping` as a last resort. It looks up ASN, prefix and
  organisation for each public hop through Team Cymru over DNS, skips private
  hops, and stops after 20 hops by default. Hop labels are approximate.

## Common options

| Option | Default | Notes |
|---|---|---|
| `-h`, `--help` | — | usage for the tool, or for a module when placed after its name |
| `--version` | — | print the DIGGER version and exit; inside the `scan` subcommand it enables service detection instead |
| `--no-color` | off | disable ANSI colours |
| `--no-banner` | off | suppress the banner |
| `--timeout <sec>` | 15 | per-request HTTP timeout |
| `-y`, `--yes` | off | assume yes for confirmation prompts |
| `--stealth` | off | enable stealth/evasion mode |
| `--i-have-permission` | off | required for stealth/evasion |
| `--concurrency <n>` | module default | global concurrency ceiling |
| `--proxy <url>` | unset | proxy for all requests |
| `--jitter <min-max>` | unset | random delay range |
| `--cache-dir <dir>` | unset | on-disk response cache |
| `--http2` | off | prefer HTTP/2 |

| Variable | Default | Notes |
|---|---|---|
| `NO_COLOR` | unset | disable colours (the standard convention) |
| `ASSUME_YES` | unset | same as `-y` |
| `HTTP_TIMEOUT` | 15 | per-request HTTP timeout in seconds |
| `HTTP_RETRIES` | 1 | retries after a failed HTTP request (two attempts total) |
| `HTTP_RETRY_DELAY` | 1 | initial retry delay in seconds |
| `HTTP_RETRY_BACKOFF` | 2 | exponential backoff multiplier for retries |
| `DIGGER_CONCURRENCY` | unset | global concurrency ceiling for all modules |
| `DIGGER_STEALTH` | unset | enable stealth/evasion mode |
| `DIGGER_I_HAVE_PERMISSION` | unset | required for stealth/evasion features |
| `DIGGER_PROXY` | unset | HTTP/SOCKS proxy URL for all requests |
| `DIGGER_PROXY_LIST` | unset | path to proxy list file (one per line) |
| `DIGGER_UA_ROTATE` | unset | rotate User-Agent from built-in pool |
| `DIGGER_JITTER` | unset | random delay range, e.g. `0.5-2` |
| `DIGGER_DELAY` | unset | base delay between requests in seconds |
| `DIGGER_CACHE_DIR` | unset | enable on-disk response cache directory |
| `DIGGER_CACHE_TTL` | 300 | cache TTL in seconds |
| `DIGGER_AUDIT_LOG` | unset | path to audit log file |
| `DIGGER_HTTP2` | unset | prefer HTTP/2 where supported |

Colours are switched off automatically when the output is not a terminal or
when `TERM=dumb`.

## Performance and stealth features

DIGGER v2.0 introduces a unified performance layer and optional stealth/evasion
capabilities, all behind an explicit authorization gate.

### Performance improvements (enabled by default)

- **Connection reuse**: all HTTP modules use `curl --keepalive-time` and HTTP/2
  where available, reducing handshake overhead.
- **DNS cache**: A/AAAA/PTR/CNAME results are cached in-memory for the duration
  of a run, eliminating duplicate lookups across modules.
- **Passive-source cache**: responses from crt.sh, certspotter, subdomain.center,
  mnemonic, hackertarget, Wayback CDX, RDAP, and ASN lookups are cached by
  normalized key to avoid re-querying the same source.
- **Shared concurrency control**: a single bounded job queue replaces per-module
  implementations. `--concurrency` / `DIGGER_CONCURRENCY` sets a global ceiling;
  stealth mode automatically lowers the default.
- **Adaptive backoff**: on HTTP 429/403/502/503 the tool increases delay and
  reduces concurrency automatically.
- **Exponential retries**: `HTTP_RETRY_DELAY` and `HTTP_RETRY_BACKOFF` control
  retry timing globally.
- **Body reuse**: modules like `info` fetch once and parse multiple times from
  the same body.

### Stealth / evasion mode (opt-in, requires `--i-have-permission`)

The following features are **disabled by default** and require an explicit
`--i-have-permission` flag (or `DIGGER_I_HAVE_PERMISSION=1`) to activate.
This is a safety guardrail: DIGGER will refuse to run stealth features without
it and will fall back to normal operation.

| Flag / env | Effect |
|---|---|
| `--stealth` / `DIGGER_STEALTH=1` | enable all stealth behaviours |
| `--i-have-permission` / `DIGGER_I_HAVE_PERMISSION=1` | **required** to run stealth mode |
| `--proxy URL` / `DIGGER_PROXY` | route all HTTP through a single proxy |
| `--proxy-list FILE` / `DIGGER_PROXY_LIST` | rotate through proxies from a file |
| `--ua-rotate` / `DIGGER_UA_ROTATE=1` | rotate User-Agent from a built-in pool |
| `--user-agent STR` | override User-Agent with a custom string |
| `--jitter MIN-MAX` / `DIGGER_JITTER` | random delay between requests (e.g. `0.5-2`) |
| `--delay SEC` / `DIGGER_DELAY` | base delay between requests |
| `--randomize-order` | shuffle probe/target order where safe |
| `--http2` / `DIGGER_HTTP2=1` | prefer HTTP/2 (also available without stealth) |
| `--audit-log FILE` / `DIGGER_AUDIT_LOG` | write an audit trail of all stealth actions |

**What stealth mode does:**
- Adds randomized delays/jitter between every request
- Rotates User-Agent on each request (when `--ua-rotate` is set)
- Rotates through a proxy list (when `--proxy-list` is set)
- Lowers default concurrency to 4
- Enables adaptive backoff on 429/403/5xx
- Randomizes request order where it does not break logic
- Logs every proxied/rotated request to the audit log (if configured)

**What stealth mode does NOT do:**
- No IP spoofing, no raw sockets, no packet crafting
- No attempt to hide the fact that requests originate from your host
- No circumvention of authentication or authorization

### On-disk response cache (optional)

```bash
./digger.sh subdomains example.com --cache-dir ~/.cache/digger --cache-ttl 3600
```

Caches raw HTTP responses and DNS results to disk. The cache respects `Cache-Control`
and `ETag` where present, and expires entries after `DIGGER_CACHE_TTL` seconds.
Disabled by default for privacy.

## Data sources

Every source is public and keyless:

- `api.ipify.org`, `ifconfig.me`, `icanhazip.com` — your public IP
- `ipwho.is`, `ip-api.com` — location, ISP, ASN and exposure flags
- `rdap.org` — registration data for domains and IP netblocks
- `dns.google`, `cloudflare-dns.com` — DNS over HTTPS, and second-resolver checks
- `crt.sh`, `api.certspotter.com` — certificate transparency
- `api.subdomain.center`, `api.mnemonic.no`, `api.hackertarget.com` — passive DNS
- `web.archive.org`, `archive.org` — historical snapshots, coverage and availability
- `blocklist.de`, `cinsscore.com`, `check.torproject.org`, `openphish.com` — threat intel
- `origin.asn.cymru.com`, `asn.cymru.com` — ASN, prefix and organisation for the path

Social checks go to the 20 platforms listed in the source. Search dorks are
built offline and are never sent by DIGGER. URLhaus is not queried: DIGGER
uses only endpoints that work without an account.

Free endpoints rate limit. When a source answers 429, 502 or an HTML error
page, modules generally report that the source is unavailable and move on
instead of pretending the target does not exist. Seeing the same warning
twice is usually the service, not your target.

## Wordlists

`wordlist/subdomains.txt` (803 labels) and `wordlist/paths.txt` (206 paths)
ship with the tool and are loaded from the script's real location (symlinks
are resolved), so they work from any working directory. Both accept `#`
comments and blank lines. The paths module needs its wordlist; the subdomain
finder and `hosts --vhosts` use the subdomain wordlist and can be pointed at a
different file with `--wordlist`.

## Output

Everything is printed to the terminal. DIGGER writes no report files and no
cache, and it creates no temporary directory; if you want a record, redirect
or tee the output yourself:

```bash
./digger.sh subdomains example.com --limit 500 | tee subdomains.txt
```

Non-interactive runs with a target print the same results, without colours or
pause prompts. Errors and warnings go to stderr, so separating the streams
works as usual.

## Tests

The regression suite is not included in this public repository. If you have a
copy of the project that includes `tests/`, the suite runs with:

```bash
bash tests/smoke.sh
```

## Reporting issues

If you run into a bug, or something in the tool does not behave the way this
README describes, please feel free to report it. Issues are welcome at:

https://github.com/tant28403-svg/DIGGER/issues

A short description of what you ran, what you expected and what happened
instead is usually enough to get started. Bug reports, feature requests and
general feedback are all appreciated.

## License

MIT — see [LICENSE](LICENSE).

Please only send traffic to hosts you own or have written permission to test.
