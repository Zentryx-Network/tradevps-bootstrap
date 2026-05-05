# ─────────────────────────────────────────────────────────────────
# modules/rdp-harden.ps1
#
# RDP hardening for a trading VPS. RDP brute-force is the #1 attack
# vector against Windows VPS — Shodan scans for port 3389 constantly
# and bots try millions of password combinations.
#
# We can't move to SSH-only (Windows admin needs RDP), but we can:
#   - Move RDP to a non-standard port (95% reduction in brute-force)
#   - Force NLA (Network Level Authentication)
#   - Disable RDP for non-admin users
#   - Enforce strong cipher suite
# ─────────────────────────────────────────────────────────────────

Step "RDP security hardening"

# ── 1. Verify RDP is enabled (it should be on a VPS) ─────────────
try {
  $rdpKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'
  $current = Get-ItemProperty -Path $rdpKey -Name 'fDenyTSConnections'
  if ($current.fDenyTSConnections -eq 1) {
    Set-ItemProperty -Path $rdpKey -Name 'fDenyTSConnections' -Value 0 -Type DWord
    OK "RDP enabled (was disabled)"
  } else {
    OK "RDP enabled (already)"
  }
} catch {
  Warn "Could not verify RDP state"
}

# ── 2. Force Network Level Authentication ────────────────────────
# Without NLA, bots can attempt password guesses without the host
# even knowing they're attacking. With NLA, every attempt requires a
# valid Kerberos / NTLM negotiation first — much higher cost.
try {
  $nlaKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp'
  Set-ItemProperty -Path $nlaKey -Name 'UserAuthentication' -Value 1 -Type DWord
  Set-ItemProperty -Path $nlaKey -Name 'SecurityLayer'      -Value 2 -Type DWord  # 2 = SSL/TLS only
  OK "NLA enforced + TLS-only RDP transport"
} catch {
  Warn "Could not enforce NLA"
}

# ── 3. (Optional) Move RDP to non-standard port ──────────────────
$rdpPort = FlagValue 'rdp-port' '3389'
if ($rdpPort -ne '3389') {
  try {
    $portKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp'
    Set-ItemProperty -Path $portKey -Name 'PortNumber' -Value ([int]$rdpPort) -Type DWord

    # Open the new port in Firewall
    New-NetFirewallRule -DisplayName "RDP custom port $rdpPort" `
      -Direction Inbound -Protocol TCP -LocalPort $rdpPort `
      -Action Allow -Profile Any -ErrorAction SilentlyContinue | Out-Null

    OK "RDP listener moved to port $rdpPort (firewall rule added)"
    Warn "REMEMBER: connect as ${env:COMPUTERNAME}:${rdpPort} from now on. Old port 3389 still open until reboot."
  } catch {
    Warn "Could not change RDP port: $($_.Exception.Message)"
  }
} else {
  Skip "RDP port unchanged (default 3389) — pass --rdp-port 53389 to randomize"
}

# ── 4. Limit RDP to Administrators group ─────────────────────────
# Removes the 'Remote Desktop Users' group from being able to log in.
# On a single-user trading VPS, only Administrator should have RDP.
try {
  $rdpUsers = 'Remote Desktop Users'
  $members = (net localgroup $rdpUsers 2>$null) -match '^[^-].*' | Where-Object {
    $_ -notmatch '^Alias|^Comment|^Members|^The command|^[-=]+$|^$'
  }
  foreach ($m in $members) {
    if ($m.Trim() -and $m.Trim() -notmatch 'Administrator') {
      net localgroup $rdpUsers $m.Trim() /delete 2>$null | Out-Null
    }
  }
  OK "RDP access restricted to Administrators only"
} catch {
  Warn "Could not modify Remote Desktop Users group"
}

# ── 5. Enable Windows Firewall (might be off on bare Windows VPS) ─
try {
  Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True
  OK "Windows Firewall enabled on all profiles"
} catch {
  Warn "Could not enable firewall"
}

# ── 6. Account lockout policy (lock after N failed RDP attempts) ─
# Brute-force defense: lock the account for 30 min after 10 failed
# password attempts. The legitimate user gets 9 retries, bots get
# their attack rate divided by 30 minutes.
try {
  net accounts /lockoutthreshold:10 /lockoutduration:30 /lockoutwindow:30 | Out-Null
  OK "Account lockout: 10 failed attempts → 30 min lock"
} catch {
  Warn "Could not configure lockout policy"
}
