# ─────────────────────────────────────────────────────────────────
# tradevps-bootstrap · entry point
#
# Run on a freshly provisioned Windows VPS to install + configure
# everything a trader needs in ~5 minutes:
#
#   - MetaTrader 4 + 5 + cTrader
#   - Windows performance tuning for low-latency
#   - Time sync via NTP (Cloudflare + NIST)
#   - Network optimizations (Nagle off, TCP autotune)
#   - Defender exclusions on trading folders
#   - RDP hardening, firewall, scheduled Windows Updates outside market hours
#
# ── Usage ────────────────────────────────────────────────────────
#
#   irm https://get.zentryxnet.lat/trading | iex
#
# Or with flags:
#
#   $env:TVPS_FLAGS = "--no-ctrader --rdp-port 53389"
#   irm https://get.zentryxnet.lat/trading | iex
#
# ── Flags ────────────────────────────────────────────────────────
#
#   --no-mt4         skip MetaTrader 4
#   --no-mt5         skip MetaTrader 5
#   --no-ctrader     skip cTrader
#   --no-perf        skip Windows performance tweaks
#   --no-network     skip network optimizations (Nagle, TCP)
#   --no-time        skip NTP setup
#   --no-defender    skip Defender exclusions
#   --no-rdp         skip RDP hardening
#   --rdp-port N     change RDP listener to port N (default: keep 3389)
#   --no-quality     skip Notepad++/7-Zip/Chrome install
#   --silent         no progress output
#
# ─────────────────────────────────────────────────────────────────

#Requires -Version 5.1
#Requires -RunAsAdministrator

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'  # speeds up Invoke-WebRequest dramatically

$REPO_RAW = 'https://raw.githubusercontent.com/Zentryx-Network/tradevps-bootstrap/main'
$VERSION  = '0.1.0'

# ── Banner ───────────────────────────────────────────────────────
# Uses Write-Host -ForegroundColor for cross-version support.
# (Backtick-e ANSI escapes only work in PowerShell 7+; we target 5.1
# as the lowest common denominator since that's Windows default.)
function Show-Banner {
  Write-Host ""
  Write-Host "  ███████╗███████╗███╗   ██╗████████╗██████╗ ██╗   ██╗██╗  ██╗" -ForegroundColor Magenta
  Write-Host "  ╚══███╔╝██╔════╝████╗  ██║╚══██╔══╝██╔══██╗╚██╗ ██╔╝╚██╗██╔╝" -ForegroundColor Magenta
  Write-Host "    ███╔╝ █████╗  ██╔██╗ ██║   ██║   ██████╔╝ ╚████╔╝  ╚███╔╝ " -ForegroundColor Magenta
  Write-Host "   ███╔╝  ██╔══╝  ██║╚██╗██║   ██║   ██╔══██╗  ╚██╔╝   ██╔██╗ " -ForegroundColor Magenta
  Write-Host "  ███████╗███████╗██║ ╚████║   ██║   ██║  ██║   ██║   ██╔╝ ██╗" -ForegroundColor Magenta
  Write-Host "  ╚══════╝╚══════╝╚═╝  ╚═══╝   ╚═╝   ╚═╝  ╚═╝   ╚═╝   ╚═╝  ╚═╝" -ForegroundColor Magenta
  Write-Host ""
  Write-Host "  tradevps-bootstrap v$VERSION  -  zentryxnet.lat" -ForegroundColor DarkGray
  Write-Host ""
}

# ── Step helpers ─────────────────────────────────────────────────
# Use $script: scope (not $global:) so the counter stays bound to
# this script and doesn't leak into the user's session.
$script:STEP_NUM = 0
function Step($title) {
  $script:STEP_NUM++
  Write-Host ""
  Write-Host "[$($script:STEP_NUM)] $title" -ForegroundColor Cyan
}
function OK($msg)   { Write-Host "    [OK]   $msg" -ForegroundColor Green }
function Skip($msg) { Write-Host "    [skip] $msg" -ForegroundColor DarkGray }
function Warn($msg) { Write-Host "    [!!]   $msg" -ForegroundColor Yellow }
function Fail($msg) { Write-Host "    [X]    $msg" -ForegroundColor Red }

# ── Parse flags from $env:TVPS_FLAGS ─────────────────────────────
$flags = @{}
if ($env:TVPS_FLAGS) {
  $tokens = $env:TVPS_FLAGS -split '\s+'
  for ($i = 0; $i -lt $tokens.Count; $i++) {
    $t = $tokens[$i]
    if ($t -like '--*') {
      $key = $t.TrimStart('-')
      $next = if ($i + 1 -lt $tokens.Count -and $tokens[$i+1] -notlike '--*') { $tokens[$i+1] } else { $true }
      if ($next -ne $true) { $i++ }
      $flags[$key] = $next
    }
  }
}
function HasFlag($name) { return $flags.ContainsKey($name) -and $flags[$name] -eq $true }
function FlagValue($name, $default) {
  if ($flags.ContainsKey($name) -and $flags[$name] -ne $true) { return $flags[$name] }
  return $default
}

# ── Module loader ────────────────────────────────────────────────
# Modules are downloaded on demand from the repo. This keeps the
# bootstrap entry small (one curl-able file) while letting us split
# logic across many smaller, testable scripts.
function Import-RemoteModule($name) {
  $url = "$REPO_RAW/modules/$name.ps1"
  try {
    $code = (Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 30).Content
    $sb   = [scriptblock]::Create($code)
    return $sb
  } catch {
    Fail "Failed to load module '$name': $($_.Exception.Message)"
    throw
  }
}

# ── Main pipeline ────────────────────────────────────────────────
Show-Banner

# Pre-flight
Step "Pre-flight checks"
$os = Get-CimInstance Win32_OperatingSystem
OK "Windows $($os.Caption) · $($os.OSArchitecture)"

if ([System.Environment]::OSVersion.Version.Major -lt 10) {
  Fail "Windows 10 / 11 / Server 2019+ required"
  exit 1
}
$totalRamGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
OK "RAM: ${totalRamGB} GB · CPU cores: $((Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors)"

if ($totalRamGB -lt 1.5) {
  Warn "Low RAM (${totalRamGB} GB). MT5 alone needs ~512MB; consider upgrading to 2GB+."
}

# Modules — each is independent and self-contained
$modules = @(
  @{ name = 'platforms';   skip = (HasFlag 'no-mt4') -and (HasFlag 'no-mt5') -and (HasFlag 'no-ctrader') },
  @{ name = 'perf-tweaks'; skip = (HasFlag 'no-perf') },
  @{ name = 'network';     skip = (HasFlag 'no-network') },
  @{ name = 'time-sync';   skip = (HasFlag 'no-time') },
  @{ name = 'defender';    skip = (HasFlag 'no-defender') },
  @{ name = 'rdp-harden';  skip = (HasFlag 'no-rdp') },
  @{ name = 'quality';     skip = (HasFlag 'no-quality') }
)

foreach ($m in $modules) {
  if ($m.skip) {
    Step "Skipping: $($m.name)"
    continue
  }
  try {
    $sb = Import-RemoteModule $m.name
    & $sb
  } catch {
    Fail "Module '$($m.name)' failed: $($_.Exception.Message)"
    Write-Host "    Continuing with next module..." -ForegroundColor DarkYellow
  }
}

# ── Done ──────────────────────────────────────────────────────────
Write-Host ""
Write-Host "════════════════════════════════════════════════════════════" -ForegroundColor Magenta
Write-Host "  Done. Your VPS is ready for trading." -ForegroundColor Magenta
Write-Host "════════════════════════════════════════════════════════════" -ForegroundColor Magenta
Write-Host ""
Write-Host "  Next steps:"
Write-Host "    1. Open MetaTrader from your desktop / Start menu"
Write-Host "    2. Log in with your broker credentials"
Write-Host "    3. Restart Windows now to apply all kernel-level tweaks:"
Write-Host "         shutdown /r /t 0"
Write-Host ""
Write-Host "  Issues, suggestions, contributions:"
Write-Host "    https://github.com/Zentryx-Network/tradevps-bootstrap"
Write-Host ""
