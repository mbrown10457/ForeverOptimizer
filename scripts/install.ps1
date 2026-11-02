<#
.SYNOPSIS
  Install ForeverOptimizer into the World of Warcraft: Forever AddOns folder on Windows.

.DESCRIPTION
  Copies the ForeverOptimizer folder from this repository into Interface\AddOns
  (default), or creates a directory junction with -Link so the game loads the
  repository copy directly (no admin rights needed for a junction).

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts\install.ps1
  powershell -ExecutionPolicy Bypass -File scripts\install.ps1 -Link
  powershell -ExecutionPolicy Bypass -File scripts\install.ps1 -AddOns "D:\Games\World of Warcraft\_forever_\Interface\AddOns"
#>
[CmdletBinding()]
param(
  [string]$AddOns = "",
  [switch]$Link
)
$ErrorActionPreference = "Stop"
$Repo  = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Addon = "ForeverOptimizer"
$Src   = Join-Path $Repo $Addon
if (-not (Test-Path (Join-Path $Src "$Addon.toc"))) { throw "Addon source not found at $Src" }

function Find-AddOnsDir {
  param([string]$Hint)
  $candidates = @()
  if ($Hint)            { $candidates += $Hint }
  if ($env:WOW_ADDONS)  { $candidates += $env:WOW_ADDONS }
  $bases = @()
  try {
    $key = Get-ItemProperty -Path "HKLM:\SOFTWARE\WOW6432Node\Blizzard Entertainment\World of Warcraft" -ErrorAction Stop
    if ($key.InstallPath) { $bases += (Split-Path -Parent $key.InstallPath.TrimEnd('\')) ; $bases += $key.InstallPath }
  } catch {}
  foreach ($root in @(${env:ProgramFiles(x86)}, $env:ProgramFiles, "C:\", "D:\", "D:\Games", "C:\Games")) {
    if ($root) { $bases += (Join-Path $root "World of Warcraft") }
  }
  foreach ($b in $bases) {
    foreach ($flavor in @("_forever_", "_camelot_")) {
      $candidates += (Join-Path (Join-Path (Join-Path $b $flavor) "Interface") "AddOns")
    }
  }
  foreach ($c in $candidates) { if ($c -and (Test-Path $c -PathType Container)) { return (Resolve-Path $c).Path } }
  foreach ($b in $bases) {
    if (Test-Path $b) { Get-ChildItem -Path $b -Directory -Filter "_*_" -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "found game folder: $($_.FullName)" } }
  }
  return $null
}

$Target = Find-AddOnsDir -Hint $AddOns
if (-not $Target) {
  Write-Host "Could not find the AddOns directory." -ForegroundColor Red
  Write-Host "Launch WoW Forever once so it creates _forever_\Interface, then re-run, or pass the path:"
  Write-Host '  scripts\install.ps1 -AddOns "C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns"'
  exit 1
}

$Dst = Join-Path $Target $Addon
if (Test-Path $Dst) {
  $item = Get-Item $Dst -Force
  if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
    Write-Host "  unlink  $Addon (existing junction)"
    [IO.Directory]::Delete($Dst)     # removes the junction only, never its target
  } else {
    Write-Host "  replace $Addon (existing folder)"
    Remove-Item -Path $Dst -Recurse -Force
  }
}

if ($Link) {
  New-Item -ItemType Junction -Path $Dst -Target $Src | Out-Null
  Write-Host "  link    $Addon -> $Src"
} else {
  Copy-Item -Path $Src -Destination $Dst -Recurse -Force
  Get-ChildItem -Path $Dst -Recurse -Force -Filter ".DS_Store" -ErrorAction SilentlyContinue | Remove-Item -Force
  Write-Host "  copy    $Addon"
}
Write-Host "AddOns dir: $Target"
Write-Host "Done. In game: /reload, then /fo help."
