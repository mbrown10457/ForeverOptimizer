# ForeverOptimizer data collector for Windows. Zips your addon data to the Desktop so you can send it.
#
# From a PowerShell window (log out of the game first so it writes the file):
#   irm https://raw.githubusercontent.com/mbrown10457/ForeverOptimizer/main/scripts/collect.ps1 | iex
#
# Optional, if the game is somewhere unusual:
#   $env:WOW_FOREVER = "D:\Games\World of Warcraft\_forever_"
#
# No parameters on purpose: a `param` block does not survive `irm | iex`.

$ErrorActionPreference = 'Stop'

function Find-GameDir {
  if ($env:WOW_FOREVER -and (Test-Path $env:WOW_FOREVER)) { return (Resolve-Path $env:WOW_FOREVER).Path }
  $bases = @()
  try {
    $key = Get-ItemProperty -Path 'HKLM:\SOFTWARE\WOW6432Node\Blizzard Entertainment\World of Warcraft' -ErrorAction Stop
    if ($key.InstallPath) { $bases += (Split-Path -Parent $key.InstallPath.TrimEnd('\')); $bases += $key.InstallPath }
  } catch {}
  foreach ($root in @(${env:ProgramFiles(x86)}, $env:ProgramFiles, 'C:\', 'D:\', 'E:\', 'C:\Games', 'D:\Games', 'E:\Games')) {
    if ($root) { $bases += (Join-Path $root 'World of Warcraft') }
  }
  foreach ($b in $bases) {
    foreach ($flavor in @('_forever_', '_camelot_')) {
      $game = Join-Path $b $flavor
      if (Test-Path $game -PathType Container) { return (Resolve-Path $game).Path }
    }
  }
  return $null
}

try {
  Write-Host ''
  Write-Host 'ForeverOptimizer data collector' -ForegroundColor Cyan
  $Game = Find-GameDir
  if (-not $Game) {
    Write-Host '  Could not find the World of Warcraft: Forever folder (_forever_).' -ForegroundColor Red
    Write-Host '  Tell the script where it is, then run the command again in the same window:'
    Write-Host '    $env:WOW_FOREVER = "D:\Games\World of Warcraft\_forever_"' -ForegroundColor Yellow
    return
  }
  $files = @(Get-ChildItem -Path (Join-Path $Game 'WTF\Account\*\SavedVariables\ForeverOptimizer.lua') -ErrorAction SilentlyContinue)
  if ($files.Count -eq 0) {
    Write-Host "  No ForeverOptimizer.lua under $Game\WTF\Account. Log out of the game once so it writes the file, then run this again." -ForegroundColor Red
    return
  }
  $stamp = Get-Date -Format 'yyyyMMdd-HHmm'
  $desktop = [Environment]::GetFolderPath('Desktop')
  $out = Join-Path $desktop "ForeverOptimizer-data-$stamp"
  New-Item -ItemType Directory -Path $out -Force | Out-Null
  $summary = @()
  foreach ($f in $files) {
    $acct = Split-Path -Leaf (Split-Path -Parent (Split-Path -Parent $f.FullName))
    Copy-Item $f.FullName (Join-Path $out "ForeverOptimizerDB-$acct.lua")
    $text = Get-Content -Raw -Path $f.FullName
    $ver = [regex]::Match($text, '\["version"\]\s*=\s*(\d+)').Groups[1].Value
    $errs = ([regex]::Matches($text, '\["where"\]\s*=')).Count
    $sessions = ([regex]::Matches($text, '\["start"\]\s*=')).Count
    $line = "account $acct  file $([math]::Round($f.Length / 1KB)) KB written $($f.LastWriteTime)  schema v$ver  errors $errs  sessions ~$sessions"
    $summary += $line
    Write-Host "  $line"
  }
  $log = Join-Path $Game 'Logs\General.log'
  if (Test-Path $log) { Copy-Item $log (Join-Path $out 'General.log') }
  $summary | Set-Content -Path (Join-Path $out 'summary.txt')
  $zip = "$out.zip"
  if (Test-Path $zip) { Remove-Item $zip -Force }
  Compress-Archive -Path "$out\*" -DestinationPath $zip
  Remove-Item -Path $out -Recurse -Force
  Write-Host ''
  Write-Host "Done. Send this file to Mike:" -ForegroundColor Green
  Write-Host "  $zip"
}
catch {
  Write-Host ''
  Write-Host "Collect failed: $($_.Exception.Message)" -ForegroundColor Red
  Write-Host '  Copy this whole window and send it to Mike.'
}
