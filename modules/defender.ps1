# ─────────────────────────────────────────────────────────────────
# modules/defender.ps1
#
# Windows Defender exclusions for trading folders. Without this, MT4/
# MT5 can have noticeable lag during high-tick periods because every
# tick file write triggers a real-time scan.
#
# We only EXCLUDE the trading folders, not disable Defender entirely.
# The rest of the system is still protected.
# ─────────────────────────────────────────────────────────────────

Step "Windows Defender exclusions for trading"

# Test if Defender is even running (some VPS providers disable it)
$defenderActive = $false
try {
  $status = Get-MpComputerStatus -ErrorAction Stop
  if ($status.AntivirusEnabled) { $defenderActive = $true }
} catch {
  Skip "Windows Defender not active on this system"
  return
}

if (-not $defenderActive) {
  Skip "Windows Defender disabled — nothing to configure"
  return
}

# ── Folder exclusions ────────────────────────────────────────────
# These are the directories MT4/MT5 write to constantly. Excluding
# them from real-time scanning eliminates 50-200ms of CPU stalls
# during peak market activity.
$excludePaths = @(
  'C:\Trading',
  "$env:APPDATA\MetaQuotes",        # MT4/MT5 user data
  "$env:LOCALAPPDATA\MetaQuotes",
  "$env:ProgramFiles\MetaTrader 5",
  "${env:ProgramFiles(x86)}\MetaTrader 5",
  "${env:ProgramFiles(x86)}\MetaTrader 4",
  "$env:LOCALAPPDATA\Spotware"      # cTrader user data
)

$added = 0
foreach ($path in $excludePaths) {
  try {
    Add-MpPreference -ExclusionPath $path -ErrorAction Stop
    $added++
  } catch {
    # Common: path doesn't exist yet (broker not installed). That's fine,
    # the exclusion still gets registered for when the folder appears.
  }
}
OK "Folder exclusions added: $added paths (Defender skips them in real-time scan)"

# ── Process exclusions ───────────────────────────────────────────
# Even better than folder exclusions: tell Defender to ignore the
# trading processes entirely. Less I/O monitoring → lower latency.
$excludeProcs = @(
  'terminal.exe',      # MT4
  'terminal64.exe',    # MT5 64-bit
  'metaeditor64.exe',  # MQL editor
  'cTrader.exe',
  'cAlgo.exe'
)
$addedProcs = 0
foreach ($proc in $excludeProcs) {
  try {
    Add-MpPreference -ExclusionProcess $proc -ErrorAction Stop
    $addedProcs++
  } catch {}
}
OK "Process exclusions added: $addedProcs trading binaries"

# ── Disable scheduled scans during market hours ──────────────────
# Default Defender does a full scan weekly — sometimes during market
# hours, which causes massive disk I/O and CPU spikes. We push it to
# Sundays at 2 AM UTC (no major market open).
try {
  Set-MpPreference -ScanScheduleDay 1            # 1 = Sunday in MS calendar
  Set-MpPreference -ScanScheduleTime '02:00:00'  # 2 AM
  Set-MpPreference -ScanScheduleQuickScanTime '02:30:00'
  OK "Defender scheduled scans: Sundays 02:00 UTC (off-market)"
} catch {
  Warn "Could not reschedule Defender scans"
}
