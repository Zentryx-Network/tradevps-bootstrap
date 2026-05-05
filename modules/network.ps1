# ─────────────────────────────────────────────────────────────────
# modules/network.ps1
#
# Network stack tuning for low-latency trading. Each tweak has a
# specific purpose for trading workloads — these aren't generic
# "make Windows faster" hacks.
# ─────────────────────────────────────────────────────────────────

Step "Network optimization"

# ── 1. Disable Nagle's algorithm ─────────────────────────────────
# Nagle's algorithm batches small TCP packets to reduce overhead. For
# trading, this adds up to 200ms latency per order send. We DON'T want
# batching — every order packet should hit the wire immediately.
#
# Setting both TcpAckFrequency=1 and TcpDelAckTicks=0 disables Nagle
# AND disables delayed ACKs (which compound the same problem).
try {
  $netInterfaces = Get-ChildItem -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces'
  foreach ($iface in $netInterfaces) {
    Set-ItemProperty -Path $iface.PSPath -Name 'TcpAckFrequency' -Value 1 -Type DWord -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $iface.PSPath -Name 'TCPNoDelay'      -Value 1 -Type DWord -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $iface.PSPath -Name 'TcpDelAckTicks'  -Value 0 -Type DWord -ErrorAction SilentlyContinue
  }
  OK "Nagle's algorithm + delayed ACKs disabled (saves up to 200ms per order)"
} catch {
  Warn "Could not disable Nagle: $($_.Exception.Message)"
}

# ── 2. TCP window auto-tuning to 'normal' ────────────────────────
# Windows sometimes ships with "highly restricted" auto-tuning which
# kills throughput on long-distance connections (LATAM <-> NY4 RTT
# ~30ms benefits enormously from larger windows).
try {
  netsh int tcp set global autotuninglevel=normal | Out-Null
  OK "TCP window auto-tuning: normal (better for long-distance trading)"
} catch {
  Warn "Could not set TCP auto-tuning"
}

# ── 3. Enable RSS (Receive Side Scaling) ─────────────────────────
# Distributes incoming network interrupts across multiple CPU cores.
# On a multi-core VPS, this prevents core 0 from becoming a bottleneck
# during high tick volume.
try {
  netsh int tcp set global rss=enabled | Out-Null
  OK "Receive Side Scaling (RSS) enabled"
} catch {
  Warn "Could not enable RSS"
}

# ── 4. Disable IPv6 if your broker doesn't use it ────────────────
# Most brokers don't have IPv6 endpoints. Windows tries IPv6 first by
# default, fails, then falls back to IPv4 — adds 1-2 second delay on
# initial connection. Skip if you actually use IPv6.
#
# We keep IPv6 enabled but DEPRIORITIZE it so IPv4 is preferred.
try {
  $ipv6Key = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters'
  Set-ItemProperty -Path $ipv6Key -Name 'DisabledComponents' -Value 0x20 -Type DWord  # prefer IPv4 over IPv6
  OK "IPv4 preferred over IPv6 in resolver"
} catch {
  Warn "Could not deprioritize IPv6"
}

# ── 5. Increase ephemeral port range ─────────────────────────────
# Default Windows ephemeral range is 49152-65535 (~16K ports). High-
# frequency trading bots that open many short-lived connections can
# exhaust this. Bumping the range to 1024-65535 gives ~64K ports.
try {
  netsh int ipv4 set dynamicport tcp start=10000 num=55000 | Out-Null
  OK "Ephemeral TCP port range: 10000-65535 (55K ports for high-frequency apps)"
} catch {
  Warn "Could not set port range"
}

# ── 6. Disable ICMP rate limiting ────────────────────────────────
# Useful if you run latency monitors / pingdom-style health checks
# from the VPS. Default Windows rate-limits ICMP at 1/sec which makes
# accurate latency measurement impossible.
try {
  netsh int ipv4 set global icmpredirects=disabled | Out-Null
  OK "ICMP redirects disabled"
} catch {
  Warn "Could not configure ICMP"
}

# ── 7. Set DNS servers to fast public resolvers ──────────────────
# Default Windows uses whatever DHCP gave us — often the host
# provider's DNS, which can be slow or unreliable. Cloudflare and
# Google are typically <5ms response and very stable.
try {
  $primaryNic = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and $_.Virtual -eq $false } | Select-Object -First 1
  if ($primaryNic) {
    Set-DnsClientServerAddress -InterfaceIndex $primaryNic.ifIndex -ServerAddresses ('1.1.1.1', '1.0.0.1', '8.8.8.8')
    OK "DNS: Cloudflare (1.1.1.1) primary, Google (8.8.8.8) fallback"
  } else {
    Warn "No active network adapter found for DNS config"
  }
} catch {
  Warn "Could not set DNS: $($_.Exception.Message)"
}
