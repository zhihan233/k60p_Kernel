# SPDX-License-Identifier: GPL-2.0-only
param(
  [string]$RunId = '45797343370',
  [string]$JobId = '139831276006',
  [int]$IntervalSec = 60,
  [int]$TimeoutMin = 55,
  [string]$Out = 'work/monitor.log',
  [switch]$Once
)
$ErrorActionPreference = 'Continue'
$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
$url = "https://github.com/zhihan233/k60p_Kernel/actions/runs/$RunId/job/$JobId"
$tmp = Join-Path $repoRoot "work/job_$JobId.html"
$pattern = 'data-name="([^"]+)"\s+data-number="(\d+)"\s+data-conclusion="([^"]*)"\s+data-external-id="[^"]*"\s+data-expand="[^"]*"\s+data-started-at="([^"]*)"\s+data-completed-at="([^"]*)"'
$deadline = (Get-Date).AddMinutes($TimeoutMin)
$last = @{}
if (-not $Once) {
  Add-Content $Out ("{0} monitor start run={1} job={2}" -f (Get-Date -Format 'HH:mm:ss'), $RunId, $JobId)
}
while ((Get-Date) -lt $deadline) {
  & curl.exe -s -L --max-time 45 -o $tmp $url 2>$null
  $raw = ''
  if (Test-Path $tmp) { $raw = Get-Content $tmp -Raw -Encoding UTF8 }
  if (-not $raw -or $raw -notmatch 'check-step') {
    Add-Content $Out ("{0} fetch failed (len={1})" -f (Get-Date -Format 'HH:mm:ss'), $raw.Length)
    if ($Once) { break }
    Start-Sleep -Seconds $IntervalSec
    continue
  }
  $steps = [regex]::Matches($raw, $pattern)
  $allDone = $steps.Count -gt 0
  foreach ($m in $steps) {
    $name = $m.Groups[1].Value
    $conc = $m.Groups[3].Value
    $started = $m.Groups[4].Value
    $completed = $m.Groups[5].Value
    if ($conc -and $conc -ne 'null') { $state = $conc }
    elseif ($started) { $state = 'running' }
    else { $state = 'pending' }
    if ($last[$name] -ne $state) {
      Add-Content $Out ("{0} {1,-46} {2,-10} started={3} completed={4}" -f (Get-Date -Format 'HH:mm:ss'), $name, $state, $started, $completed)
      $last[$name] = $state
    }
    if (-not ($conc -and $conc -ne 'null') -and $name -notmatch '^Post Run') { $allDone = $false }
  }
  if ($allDone) {
    Add-Content $Out ("{0} all steps concluded" -f (Get-Date -Format 'HH:mm:ss'))
    break
  }
  if ($Once) { break }
  Start-Sleep -Seconds $IntervalSec
}
Add-Content $Out ("{0} monitor end" -f (Get-Date -Format 'HH:mm:ss'))
