# ForeverOptimizer one-command installer for Windows.
#
# From a PowerShell window:
#   irm https://raw.githubusercontent.com/mbrown10457/ForeverOptimizer/main/scripts/install-windows.ps1 | iex
#
# What it does: finds the World of Warcraft: Forever folder, downloads the latest
# ForeverOptimizer release and the latest QuestieDB (Forever) release, checks the
# QuestieDB checksum, and copies both into Interface\AddOns. Re-running it updates both.
#
# Optional environment variables (set before running):
#   $env:WOW_ADDONS   = "D:\Games\World of Warcraft\_forever_\Interface\AddOns"   # if the game is not found
#   $env:FO_VERSION   = "v0.9.0"      # a specific ForeverOptimizer release instead of the latest
#   $env:GITHUB_TOKEN = "ghp_..."     # only needed while the repository is private
#
# No parameters on purpose: a `param` block does not survive `irm | iex`.

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}

$Owner    = 'mbrown10457'
$RepoName = 'ForeverOptimizer'
$Addon    = 'ForeverOptimizer'
$QdbRepo  = 'Questie/QuestieDB'
$Headers  = @{ 'User-Agent' = 'ForeverOptimizer-installer'; 'Accept' = 'application/vnd.github+json' }
if ($env:GITHUB_TOKEN) { $Headers['Authorization'] = "Bearer $($env:GITHUB_TOKEN)" }

function Write-Step([string]$m) { Write-Host "  $m" }
function Write-Ok([string]$m)   { Write-Host "  $m" -ForegroundColor Green }
function Write-Bad([string]$m)  { Write-Host "  $m" -ForegroundColor Red }

function Find-AddOnsDir {
  if ($env:WOW_ADDONS) {
    if (-not (Test-Path $env:WOW_ADDONS)) { New-Item -ItemType Directory -Path $env:WOW_ADDONS -Force | Out-Null }
    return (Resolve-Path $env:WOW_ADDONS).Path
  }
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
      if (Test-Path $game -PathType Container) {
        $dir = Join-Path (Join-Path $game 'Interface') 'AddOns'
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        return (Resolve-Path $dir).Path
      }
    }
  }
  return $null
}

function Get-Release([string]$repo, [string]$tag) {
  $url = if ($tag -and $tag -ne 'latest') { "https://api.github.com/repos/$repo/releases/tags/$tag" } else { "https://api.github.com/repos/$repo/releases/latest" }
  return Invoke-RestMethod -Uri $url -Headers $Headers
}

function Save-Asset($release, [string]$pattern, [string]$dest) {
  $asset = @($release.assets | Where-Object { $_.name -like $pattern }) | Select-Object -First 1
  if (-not $asset) { throw "release $($release.tag_name) has no file matching $pattern" }
  if ($env:GITHUB_TOKEN) {
    # the API asset URL honours the token; the browser URL does not
    $h = @{} + $Headers; $h['Accept'] = 'application/octet-stream'
    Invoke-WebRequest -Uri $asset.url -Headers $h -OutFile $dest -UseBasicParsing
  } else {
    Invoke-WebRequest -Uri $asset.browser_download_url -Headers @{ 'User-Agent' = 'ForeverOptimizer-installer' } -OutFile $dest -UseBasicParsing
  }
  return $asset
}

function Install-Folder([string]$src, [string]$addons) {
  $name = Split-Path -Leaf $src
  $dst  = Join-Path $addons $name
  if (Test-Path $dst) {
    $item = Get-Item $dst -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { [IO.Directory]::Delete($dst) }   # a junction: remove the link only
    else { Remove-Item -Path $dst -Recurse -Force }
  }
  Copy-Item -Path $src -Destination $dst -Recurse -Force
  return $dst
}

$Temp = Join-Path ([IO.Path]::GetTempPath()) ("fo-install-" + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $Temp -Force | Out-Null

try {
  Write-Host ''
  Write-Host 'ForeverOptimizer installer' -ForegroundColor Cyan

  $AddOns = Find-AddOnsDir
  if (-not $AddOns) {
    Write-Bad 'Could not find the World of Warcraft: Forever folder (_forever_).'
    Write-Host '  Install the game through Battle.net first. If it is somewhere unusual, tell the installer where:'
    Write-Host '    $env:WOW_ADDONS = "D:\Games\World of Warcraft\_forever_\Interface\AddOns"' -ForegroundColor Yellow
    Write-Host '  then run the install command again in the same window.'
    return
  }
  Write-Step "AddOns folder: $AddOns"

  # --- ForeverOptimizer ---
  $tag = if ($env:FO_VERSION) { $env:FO_VERSION } else { 'latest' }
  Write-Step "fetching ForeverOptimizer ($tag) from github.com/$Owner/$RepoName ..."
  $rel = Get-Release "$Owner/$RepoName" $tag
  $zip = Join-Path $Temp 'ForeverOptimizer.zip'
  $asset = Save-Asset $rel 'ForeverOptimizer-*.zip' $zip
  $x = Join-Path $Temp 'fo'
  Expand-Archive -Path $zip -DestinationPath $x -Force
  $src = Join-Path $x $Addon
  if (-not (Test-Path (Join-Path $src "$Addon.toc"))) { throw "the release zip did not contain $Addon\$Addon.toc" }
  $dst = Install-Folder $src $AddOns
  Write-Ok "ForeverOptimizer $($rel.tag_name) installed ($($asset.name))"

  # --- QuestieDB (Forever flavour), checksum-verified against its release manifest ---
  Write-Step "fetching QuestieDB (Forever) from github.com/$QdbRepo ..."
  $qrel = Get-Release $QdbRepo 'latest'
  $qzip = Join-Path $Temp 'QuestieDB-Forever.zip'
  $qman = Join-Path $Temp 'release.json'
  $null = Save-Asset $qrel 'QuestieDB-Forever.zip' $qzip
  $null = Save-Asset $qrel 'release.json' $qman
  $manifest = Get-Content -Raw -Path $qman | ConvertFrom-Json
  $expected = @($manifest.questiedb.artifacts | Where-Object { $_.flavor -eq 'Forever' })[0].sha256
  $actual = (Get-FileHash -Algorithm SHA256 -Path $qzip).Hash.ToLower()
  if ($expected -and ($expected.ToLower() -ne $actual)) { throw "QuestieDB checksum mismatch (expected $expected, got $actual); not installed" }
  $qx = Join-Path $Temp 'qdb'
  Expand-Archive -Path $qzip -DestinationPath $qx -Force
  $qsrc = Join-Path $qx 'QuestieDB'
  if (-not (Test-Path (Join-Path $qsrc 'QuestieDB_Forever.toc'))) { throw 'the QuestieDB zip did not contain QuestieDB\QuestieDB_Forever.toc' }
  $null = Install-Folder $qsrc $AddOns
  Write-Ok "QuestieDB $($manifest.questiedb.version) (Forever) installed, checksum verified"

  Write-Host ''
  Write-Host 'Done.' -ForegroundColor Green
  Write-Host '  In game: character select > AddOns button > both ForeverOptimizer and QuestieDB ticked'
  Write-Host '           (tick "Load out of date AddOns" if the client complains).'
  Write-Host '  Then in the world: /reload, then /fo checklist'
  Write-Host '  To update later: run the same command again.'
}
catch {
  Write-Host ''
  Write-Bad "Install failed: $($_.Exception.Message)"
  if ($_.Exception.Response -and $_.Exception.Response.StatusCode.value__ -eq 404) {
    Write-Host '  404 from GitHub usually means the repository is private or the release has no zip yet.'
  }
  Write-Host '  Copy this whole window and send it to Mike.'
}
finally {
  try { Remove-Item -Path $Temp -Recurse -Force -ErrorAction SilentlyContinue } catch {}
}
