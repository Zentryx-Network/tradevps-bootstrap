# ─────────────────────────────────────────────────────────────────
# modules/quality.ps1
#
# Quality of life software: text editor with MQL highlighting, 7-Zip,
# a real browser. Installed via winget (built into Win10 1809+ and
# all of Windows 11 / Server 2022+).
#
# Why winget instead of chocolatey: winget is now built-in, no 3rd
# party install needed, signed by Microsoft, plays well with Windows
# Update.
# ─────────────────────────────────────────────────────────────────

Step "Quality of life: editor, archiver, browser"

# Check winget is available
$wingetOk = $false
try {
  $null = Get-Command winget -ErrorAction Stop
  $wingetOk = $true
} catch {
  Warn "winget not available — falling back to direct installer downloads"
}

# Helper that uses winget if available, otherwise downloads direct.
function Install-Tool($wingetId, $name, $directUrl, $installerArgs) {
  if ($wingetOk) {
    try {
      Write-Host "    Installing $name via winget..." -ForegroundColor DarkCyan
      $null = winget install --id $wingetId --silent --accept-package-agreements --accept-source-agreements --disable-interactivity 2>&1
      OK "$name installed (winget)"
      return
    } catch {
      Warn "winget install failed for $name — trying direct download"
    }
  }
  if ($directUrl) {
    try {
      $tmp = "$env:TEMP\$($name -replace '\s','-').exe"
      Invoke-WebRequest -Uri $directUrl -OutFile $tmp -UseBasicParsing -TimeoutSec 120
      Start-Process -FilePath $tmp -ArgumentList $installerArgs -Wait
      OK "$name installed (direct)"
    } catch {
      Fail "$name install failed: $($_.Exception.Message)"
    }
  } else {
    Skip "$name (no direct fallback)"
  }
}

# ── Notepad++ ────────────────────────────────────────────────────
# Best free text editor with MQL syntax highlighting plugin available.
# Trader will write/edit Expert Advisors, indicators, scripts — needs
# better than Notepad.
Install-Tool 'Notepad++.Notepad++' 'Notepad++' `
  'https://github.com/notepad-plus-plus/notepad-plus-plus/releases/download/v8.6.9/npp.8.6.9.Installer.x64.exe' `
  '/S'

# ── 7-Zip ────────────────────────────────────────────────────────
# Brokers distribute MT4/MT5 templates and EAs as .zip / .rar / .7z.
# 7-Zip handles all three; built-in Windows extractor only does .zip.
Install-Tool '7zip.7zip' '7-Zip' `
  'https://www.7-zip.org/a/7z2408-x64.exe' `
  '/S'

# ── Google Chrome ────────────────────────────────────────────────
# Trader needs a real browser for TradingView, broker web platforms,
# market news. Edge ships with Windows but Chrome has better extension
# ecosystem (uBlock, TradingView Tools, etc).
Install-Tool 'Google.Chrome' 'Google Chrome' `
  'https://dl.google.com/chrome/install/standalonesetup64.exe' `
  '/silent /install'

# ── Git for Windows (optional but useful) ────────────────────────
# Many algo traders fork EAs from GitHub. Having git installed makes
# pulling updates trivial vs downloading zips.
Install-Tool 'Git.Git' 'Git for Windows' $null $null

# ── Python 3 (optional, for script-based traders) ────────────────
# Many "MT5 + Python" hybrid setups need Python. The MT5 Python
# integration package is built into MT5 already, but the language
# runtime needs separate install.
Install-Tool 'Python.Python.3.12' 'Python 3.12' $null $null
