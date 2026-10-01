# CrossForge · Windows installer for opencode
#
#   irm https://github.com/ziprecovery26/crossforge/releases/latest/download/install.ps1 | iex
#
# Env overrides: $env:CROSSFORGE_REPO, $env:CROSSFORGE_PROJECT, $env:CROSSFORGE_VERSION
$ErrorActionPreference = "Stop"

$Repo    = if ($env:CROSSFORGE_REPO)    { $env:CROSSFORGE_REPO }    else { "ziprecovery26/crossforge" }
$Project = if ($env:CROSSFORGE_PROJECT) { $env:CROSSFORGE_PROJECT } else { "opencode" }
$Version = if ($env:CROSSFORGE_VERSION) { $env:CROSSFORGE_VERSION } else { "latest" }

function Say($m) { Write-Host "[crossforge] $m" -ForegroundColor Cyan }
function Die($m) { Write-Host "[crossforge][error] $m" -ForegroundColor Red; exit 1 }

$arch = $env:PROCESSOR_ARCHITECTURE
$target = switch ($arch) {
  "AMD64" { "windows-x64" }
  "ARM64" { "windows-arm64" }
  default { Die "Unsupported architecture: $arch" }
}

$base = if ($Version -eq "latest") {
  "https://github.com/$Repo/releases/latest/download"
} else {
  "https://github.com/$Repo/releases/download/$Version"
}

$asset = "$Project-$target.zip"
$tmp = Join-Path $env:TEMP ("crossforge-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tmp | Out-Null

try {
  Say "platform: $target"
  Say "downloading $asset"
  $zip = Join-Path $tmp $asset
  Invoke-WebRequest -Uri "$base/$asset" -OutFile $zip -UseBasicParsing

  # checksum verification
  try {
    $sums = Join-Path $tmp "SHA256SUMS"
    Invoke-WebRequest -Uri "$base/SHA256SUMS" -OutFile $sums -UseBasicParsing
    $expected = (Get-Content $sums | Where-Object { $_ -match [regex]::Escape($asset) }) -split "\s+" | Select-Object -First 1
    $actual = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
    if ($expected -and ($expected.ToLower() -ne $actual)) { Die "checksum mismatch — refusing to install" }
    Say "checksum ok"
  } catch [System.Net.WebException] {
    Say "SHA256SUMS not published, skipping verification"
  }

  Say "extracting"
  Expand-Archive -Path $zip -DestinationPath $tmp -Force

  $dest = Join-Path $env:LOCALAPPDATA "Programs\$Project"
  New-Item -ItemType Directory -Force -Path $dest | Out-Null

  $exe = Get-ChildItem -Path $tmp -Filter "$Project.exe" -Recurse | Select-Object -First 1
  if (-not $exe) { Die "binary not found inside archive" }
  Copy-Item $exe.FullName (Join-Path $dest "$Project.exe") -Force

  $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
  if ($userPath -notlike "*$dest*") {
    [Environment]::SetEnvironmentVariable("Path", "$userPath;$dest", "User")
    Say "added to PATH: $dest  (naya terminal kholo)"
  }

  Say "installed → $(Join-Path $dest "$Project.exe")"
  & (Join-Path $dest "$Project.exe") --version
  Say "done ✅"
} finally {
  Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}
