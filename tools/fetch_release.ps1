# SPDX-License-Identifier: MIT
param(
  [string]$Tag = 'k60p-kernel-los-v1',
  [string]$OutDir = 'deliver',
  [string[]]$Files = @('boot-los.img', 'ak3-los.zip', 'Image-los', 'SHA256SUMS-los', 'abi-report-los.json', 'build-los.json', 'kernel-los.config')
)
$ErrorActionPreference = 'Continue'
$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot
New-Item -ItemType Directory -Force $OutDir | Out-Null
$ok = $true
foreach ($f in $Files) {
  $dest = Join-Path $OutDir $f
  $url = "https://github.com/zhihan233/k60p_Kernel/releases/download/$Tag/$f"
  & curl.exe -fsSL --retry 3 --retry-delay 2 --max-time 300 -o $dest $url 2>$null
  if ($LASTEXITCODE -ne 0 -or -not (Test-Path $dest)) {
    Write-Host "FAILED: $f"
    $ok = $false
    continue
  }
  $len = (Get-Item $dest).Length
  Write-Host ("OK {0,-22} {1,10} bytes" -f $f, $len)
}
if ($ok) { Write-Host "all assets downloaded to $OutDir" } else { Write-Host "some assets missing"; exit 1 }
