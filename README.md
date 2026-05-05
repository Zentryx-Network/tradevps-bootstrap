# tradevps-bootstrap

> Set up a Windows VPS for trading in **5 minutes**, not 3 hours.

A single PowerShell script that turns a freshly provisioned Windows VPS
into a production-ready trading environment: MetaTrader 4/5, cTrader,
TradingView, performance tweaks, RDP hardening, NTP precision, and
network optimizations tuned specifically for low-latency order
execution.

## Install

Open PowerShell **as Administrator** on your VPS and run:

```powershell
irm https://get.zentryxnet.lat/trading | iex
```

That's it. The script:

1. Asks no questions (sensible defaults)
2. Downloads + installs trading platforms
3. Tunes Windows for low-latency
4. Hardens RDP against brute-force
5. Configures NTP to 4 redundant time sources
6. Adds Defender exclusions (50-200ms tick processing improvement)

After it finishes, **reboot once** to apply kernel-level tweaks
(`shutdown /r /t 0`).

## What it installs / configures

| Module | What it does |
|---|---|
| **Platforms** | MetaTrader 5 (silent install) · cTrader (silent install) · TradingView shortcut · MT4 install guide (broker-specific) · folder layout `C:\Trading\{MT4,MT5,cTrader,EAs,Indicators,Logs}` |
| **Performance** | High Performance power plan · disable hibernation · disable Search Indexer + SuperFetch · high-precision platform timer · UTC timezone · show file extensions |
| **Network** | **Disable Nagle's algorithm + delayed ACKs** (saves up to 200ms per order) · TCP autotune normal · RSS · ephemeral port range 10000-65535 · DNS to Cloudflare + Google |
| **Time sync** | NTP peers: time.cloudflare.com, time.google.com, time.nist.gov, pool.ntp.org · poll every 64 seconds (default Windows is once a week) |
| **Defender** | Folder + process exclusions for MT4/MT5/cTrader · scheduled scans moved to Sundays 02:00 UTC |
| **RDP harden** | NLA enforced · TLS-only transport · account lockout 10 attempts → 30 min · firewall enabled · optional custom port |
| **Quality** | Notepad++ (MQL syntax) · 7-Zip · Google Chrome · Git · Python 3.12 · all via winget |

## Customization

Set environment variable `TVPS_FLAGS` before running to skip parts:

```powershell
$env:TVPS_FLAGS = "--no-ctrader --no-quality --rdp-port 53389"
irm https://get.zentryxnet.lat/trading | iex
```

| Flag | Effect |
|---|---|
| `--no-mt4` | Skip MT4 install |
| `--no-mt5` | Skip MT5 install |
| `--no-ctrader` | Skip cTrader install |
| `--no-perf` | Skip Windows performance tweaks |
| `--no-network` | Skip network optimizations |
| `--no-time` | Skip NTP setup |
| `--no-defender` | Skip Defender exclusions |
| `--no-rdp` | Skip RDP hardening (keep all defaults) |
| `--rdp-port N` | Change RDP listener to port N (default: 3389) |
| `--no-quality` | Skip Notepad++/7-Zip/Chrome/Git/Python install |

## Why this exists

Most VPS providers (including the big-name ones) deliver a bare
Windows install. That means traders spend the first 2-3 hours of every
new VPS:

- Manually installing MT4/MT5/cTrader from broker links
- Googling "Windows performance tuning for trading" and applying random
  registry tweaks of dubious origin
- Forgetting to disable Nagle's algorithm and wondering why their
  scalping bot misses fills
- Running default Windows time sync and getting "clock skew" errors
  from the broker
- Leaving RDP on port 3389 and finding 8,000 brute-force attempts in
  the logs the next morning

This script bundles every one of those tasks into a single
`irm | iex` line, with sensible defaults from years of operating
trading infrastructure for clients.

## Requirements

- Windows 10 / 11 / Server 2019+ (Server 2022 recommended)
- Administrator PowerShell (the script self-checks via `#Requires
  -RunAsAdministrator`)
- Internet connectivity (downloads ~150 MB of installers)
- Minimum 1.5 GB RAM (2 GB+ recommended for MT5)

## Security

- Installer URLs are pinned to official vendors (MetaQuotes, Spotware,
  Notepad++, 7-Zip, etc.)
- The script is open source — read it before running. **Never trust
  random `irm | iex` pipes without auditing the code.**
- Defender exclusions are scoped to trading folders only; the rest of
  the system is still protected
- RDP hardening defaults (NLA + TLS) are stricter than Windows out of
  the box

## Contributing

Pull requests welcome — especially for:

- Additional broker installer URLs (we accept manual mappings)
- Linux equivalents (`tradevps-bootstrap-linux` for traders running
  Wine + MT5 on Ubuntu)
- macOS equivalents (less common but real)
- Unit tests via Pester

Open an issue first if you're proposing a non-trivial change.

## License

MIT. See [LICENSE](./LICENSE).

---

Built by [Zentryx Network](https://zentryxnet.lat) — a cloud hosting
provider for LATAM that uses this script in production. If you need
infrastructure where this kind of tuning actually shows up in your fill
rates, [check us out](https://zentryxnet.lat/vps#use-cases).

But the script works on **any** Windows VPS — Hetzner, OVH, Vultr,
DigitalOcean, your own bare metal. That's the point.
