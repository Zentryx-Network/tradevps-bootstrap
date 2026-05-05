# ─────────────────────────────────────────────────────────────────
# modules/platforms.ps1
#
# Downloads and silent-installs the trading platforms a typical
# retail/algo trader uses. Skips any platform whose --no-* flag is set.
#
# Note on installer URLs: brokers redistribute MT4/MT5 with their own
# rebranding. The "vanilla" installer from MetaQuotes does not exist
# publicly anymore (deprecated since 2022). We use a generic broker-
# neutral redistributor + cTrader's official URL.
#
# If a download fails (broker URLs change frequently), we log it and
# move on — the trader can install manually after if needed.
# ─────────────────────────────────────────────────────────────────

Step "Trading platforms"

# Create canonical folder structure
$tradingRoot = 'C:\Trading'
$folders = @('MT4', 'MT5', 'cTrader', 'Logs', 'EAs', 'Indicators')
foreach ($f in $folders) {
  $path = Join-Path $tradingRoot $f
  if (-not (Test-Path $path)) {
    New-Item -ItemType Directory -Force -Path $path | Out-Null
  }
}
OK "Folder layout ready: $tradingRoot"

# ── MetaTrader 5 (FXPro neutral redistributor) ───────────────────
if (-not (HasFlag 'no-mt5')) {
  $mt5Installer = "$env:TEMP\mt5setup.exe"
  $mt5Url = 'https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe'

  try {
    Write-Host "    Downloading MetaTrader 5..." -ForegroundColor DarkCyan
    Invoke-WebRequest -Uri $mt5Url -OutFile $mt5Installer -UseBasicParsing -TimeoutSec 120
    Write-Host "    Installing (silent)..." -ForegroundColor DarkCyan
    # /auto runs the installer with sensible defaults, no UI
    Start-Process -FilePath $mt5Installer -ArgumentList '/auto' -Wait
    OK "MetaTrader 5 installed"
  } catch {
    Fail "MT5 install failed: $($_.Exception.Message)"
    Warn "Download manually from your broker if needed"
  }
} else {
  Skip "MetaTrader 5 (--no-mt5)"
}

# ── MetaTrader 4 ─────────────────────────────────────────────────
# MT4 reached EOL in 2022 from MetaQuotes but most brokers still
# redistribute. We can't bundle a generic installer reliably, so we
# create a placeholder + URL for the most common brokers.
if (-not (HasFlag 'no-mt4')) {
  $mt4Note = @'
MetaTrader 4 install note
─────────────────────────
MT4 is no longer distributed by MetaQuotes. Download the version from
YOUR broker (the broker-branded MT4 has their server preconfigured).

Most common broker downloads:
  - IC Markets:     https://www.icmarkets.com/global/en/trading-platforms/metatrader-4
  - Pepperstone:    https://pepperstone.com/en/trading/platforms/metatrader-4/
  - XM:             https://www.xm.com/mt4
  - FXPro:          https://www.fxpro.com/trading-platforms/mt4
  - Exness:         https://www.exness.com/platforms/mt4/

Save the installer to C:\Trading\MT4\ for consistency.
'@
  $mt4Note | Out-File -FilePath 'C:\Trading\MT4\README-MT4.txt' -Encoding UTF8
  OK "MT4 readme created at C:\Trading\MT4\README-MT4.txt (broker-specific install)"
} else {
  Skip "MetaTrader 4 (--no-mt4)"
}

# ── cTrader ──────────────────────────────────────────────────────
if (-not (HasFlag 'no-ctrader')) {
  $ctInstaller = "$env:TEMP\ctrader-setup.exe"
  $ctUrl = 'https://getctrader.com/spotware/ctrader/builds/release/ctrader.exe'

  try {
    Write-Host "    Downloading cTrader..." -ForegroundColor DarkCyan
    Invoke-WebRequest -Uri $ctUrl -OutFile $ctInstaller -UseBasicParsing -TimeoutSec 120
    Write-Host "    Installing (silent)..." -ForegroundColor DarkCyan
    Start-Process -FilePath $ctInstaller -ArgumentList '/SILENT', '/NORESTART' -Wait
    OK "cTrader installed"
  } catch {
    Fail "cTrader install failed: $($_.Exception.Message)"
    Warn "Download manually from spotware.com if needed"
  }
} else {
  Skip "cTrader (--no-ctrader)"
}

# ── TradingView shortcut ─────────────────────────────────────────
# TradingView is web-only — just create a shortcut to launch in default browser.
$tvLnk = [Environment]::GetFolderPath('Desktop') + '\TradingView.url'
@"
[InternetShortcut]
URL=https://www.tradingview.com/chart/
IconIndex=0
"@ | Out-File -FilePath $tvLnk -Encoding ASCII
OK "TradingView desktop shortcut created"
