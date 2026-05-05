# ─────────────────────────────────────────────────────────────────
# modules/time-sync.ps1
#
# NTP setup for accurate time on the VPS. Critical for trading
# because order timestamps that diverge by >1 second from broker
# server time often get rejected ("clock skew" errors) or logged
# with confusing offsets.
#
# Windows default time sync uses time.windows.com with checks every
# week — too infrequent for a trading box. We point to multiple
# stratum-1 sources and force more frequent syncs.
# ─────────────────────────────────────────────────────────────────

Step "Time synchronization (NTP)"

# Ensure W32Time service is running and configured
try {
  Set-Service -Name 'W32Time' -StartupType Automatic
  Start-Service -Name 'W32Time' -ErrorAction SilentlyContinue
  OK "W32Time service: Automatic"
} catch {
  Warn "Could not configure W32Time service"
}

# ── Set NTP peer list ────────────────────────────────────────────
# We use 4 sources for redundancy + cross-check:
#   - time.cloudflare.com    (anycast, very low latency, stratum-2)
#   - time.google.com        (stratum-1, smeared leap seconds)
#   - time.nist.gov          (US official, stratum-1)
#   - pool.ntp.org           (community fallback)
$ntpPeers = 'time.cloudflare.com,0x9 time.google.com,0x9 time.nist.gov,0x9 pool.ntp.org,0x9'
# 0x9 = SpecialInterval flag; w32time will use the SpecialPollInterval below.

try {
  w32tm /config /manualpeerlist:"$ntpPeers" /syncfromflags:manual /reliable:YES /update | Out-Null
  OK "NTP peers: Cloudflare, Google, NIST, pool.ntp.org"
} catch {
  Warn "w32tm config failed: $($_.Exception.Message)"
}

# ── More aggressive sync interval ────────────────────────────────
# Default is 7 days between sync attempts. For trading we want every
# 64 seconds (=2^6, the smallest reasonable interval that doesn't
# trigger rate-limiting on public NTP servers).
try {
  $ntpClient = 'HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\TimeProviders\NtpClient'
  Set-ItemProperty -Path $ntpClient -Name 'SpecialPollInterval' -Value 64 -Type DWord
  OK "NTP poll interval: 64 seconds"
} catch {
  Warn "Could not set NTP poll interval"
}

# ── Force a sync now ─────────────────────────────────────────────
try {
  Restart-Service -Name 'W32Time' -Force
  Start-Sleep -Seconds 3
  w32tm /resync /force 2>$null | Out-Null
  $status = w32tm /query /status 2>$null | Out-String
  if ($status -match 'Source:\s+(.+)') {
    OK "Synced from: $($Matches[1].Trim())"
  } else {
    OK "NTP service restarted, sync in progress"
  }
} catch {
  Warn "Initial sync failed (will retry on next interval)"
}
