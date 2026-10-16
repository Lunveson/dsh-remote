# dsh-link - stop. Called by stop-silent.vbs
$ErrorActionPreference = "SilentlyContinue"
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$pidFile = Join-Path $dir ".dsh-link.pid"

if (Test-Path $pidFile) {
  $targetPid = (Get-Content $pidFile -ErrorAction SilentlyContinue | Select-Object -First 1)
  if ($targetPid) { Stop-Process -Id $targetPid -Force -ErrorAction SilentlyContinue }
  Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
}

Get-CimInstance Win32_Process -Filter "Name='java.exe'" -ErrorAction SilentlyContinue |
  Where-Object { $_.CommandLine -match "DshLink" } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
