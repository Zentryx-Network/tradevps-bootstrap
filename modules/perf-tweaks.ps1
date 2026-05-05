# ─────────────────────────────────────────────────────────────────
# modules/perf-tweaks.ps1
#
# Windows performance tuning for low-latency trading workloads.
#
# Each tweak is documented with the "why" because some are
# counter-intuitive (e.g., disabling Windows Defender real-time scan
# on the trading folder is huge for MT5 tick processing latency).
# ─────────────────────────────────────────────────────────────────

Step "Performance tuning"

# ── 1. Power plan to High Performance ────────────────────────────
# Default Balanced power plan throttles CPU dynamically. For trading
# we want CPU at full clock 24/7. Cost: a couple watts more on the host.
try {
  powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c | Out-Null  # GUID for "High performance"
  OK "Power plan: High Performance"
} catch {
  Warn "Could not set High Performance power plan: $($_.Exception.Message)"
}

# ── 2. Disable hibernation ───────────────────────────────────────
# Trading VPS doesn't sleep — hibernation file just wastes 4-8GB disk.
try {
  powercfg /hibernate off
  OK "Hibernation disabled (frees disk space)"
} catch {
  Warn "Could not disable hibernation"
}

# ── 3. Visual effects → Performance ──────────────────────────────
# Animations, fade effects, smooth scroll — irrelevant on a VPS
# accessed via RDP. Disabling them frees ~50MB RAM and reduces
# RDP bandwidth significantly.
$key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'
New-Item -Path $key -Force | Out-Null
Set-ItemProperty -Path $key -Name 'VisualFXSetting' -Value 2 -Type DWord  # 2 = best performance
OK "Visual effects: Performance preset"

# ── 4. Disable Search Indexer ────────────────────────────────────
# The Search service indexes every file change. On a trading box
# with thousands of tick files written/sec, this is a huge CPU drain.
# Trader will use folder navigation, not Windows Search.
try {
  Stop-Service -Name 'WSearch' -Force -ErrorAction SilentlyContinue
  Set-Service  -Name 'WSearch' -StartupType Disabled
  OK "Search Indexer (WSearch) disabled"
} catch {
  Warn "Could not disable Search Indexer"
}

# ── 5. Disable SysMain (Superfetch) ──────────────────────────────
# SuperFetch pre-loads "frequently used" apps to RAM. On a trading
# VPS the only frequently-used app is MT5, which is always running
# anyway. SysMain just causes random disk I/O at unpredictable times.
try {
  Stop-Service -Name 'SysMain' -Force -ErrorAction SilentlyContinue
  Set-Service  -Name 'SysMain' -StartupType Disabled
  OK "SysMain (Superfetch) disabled"
} catch {
  Warn "Could not disable SysMain"
}

# ── 6. High-precision timer ──────────────────────────────────────
# Windows defaults to a low-resolution timer (15.6ms). Some trading
# apps and especially low-latency network code benefit from 1ms tick.
# The change persists across reboots via bcdedit.
try {
  bcdedit /set useplatformtick yes 2>$null | Out-Null
  bcdedit /set useplatformclock yes 2>$null | Out-Null
  OK "High-precision platform timer enabled (requires reboot)"
} catch {
  Warn "Could not set platform timer (may require Windows Server)"
}

# ── 7. Disable telemetry / Cortana / Tips ────────────────────────
# Background telemetry processes ping Microsoft constantly. On a
# trading box, every wasted CPU cycle is one less available for tick
# processing.
$telemetryKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'
if (-not (Test-Path $telemetryKey)) {
  New-Item -Path $telemetryKey -Force | Out-Null
}
Set-ItemProperty -Path $telemetryKey -Name 'AllowTelemetry' -Value 0 -Type DWord
OK "Telemetry minimized"

# ── 8. Page file: managed by Windows OR fixed at 1.5x RAM ────────
# Trading apps don't generally swap, but a small fixed page file
# prevents Windows from thrashing if RAM gets unexpectedly tight.
$totalRamMB = [math]::Floor((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1MB)
$pagefileMB = [math]::Floor($totalRamMB * 1.5)
try {
  $cs = Get-WmiObject Win32_ComputerSystem -EnableAllPrivileges
  $cs.AutomaticManagedPagefile = $false
  $cs.Put() | Out-Null

  # Remove any existing pagefile, then create a fixed-size one on C:
  Get-WmiObject -Query "SELECT * FROM Win32_PageFileSetting" | ForEach-Object { $_.Delete() } 2>$null
  Set-WmiInstance -Class Win32_PageFileSetting -Arguments @{
    name = 'C:\pagefile.sys'
    InitialSize = $pagefileMB
    MaximumSize = $pagefileMB
  } | Out-Null
  OK "Page file: fixed ${pagefileMB} MB on C:"
} catch {
  Warn "Could not set page file: $($_.Exception.Message)"
}

# ── 9. Set timezone to UTC ───────────────────────────────────────
# Industry standard for trading: all logs and order timestamps in UTC.
# Eliminates DST confusion when comparing executions across brokers.
try {
  Set-TimeZone -Id 'UTC'
  OK "Timezone set to UTC (industry standard for trading)"
} catch {
  Warn "Could not set UTC timezone"
}

# ── 10. Show file extensions + hidden files in Explorer ──────────
# Sysadmin / dev quality of life. Hidden by default in Windows is
# absurd for any technical user.
$explorer = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
Set-ItemProperty -Path $explorer -Name 'HideFileExt'   -Value 0 -Type DWord
Set-ItemProperty -Path $explorer -Name 'Hidden'        -Value 1 -Type DWord
OK "Explorer: file extensions + hidden files visible"
