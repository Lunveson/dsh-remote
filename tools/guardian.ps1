# ============================================================
#  guardian.ps1 —— 守护进程（v2，带单实例锁）
#
#  每 15 秒检查：
#    · dsh（DeepSeek Harness）→ 不在就启动
#    · dsh-link 代理          → 不在就启动
#
#  ★单实例★：用命名 Mutex，重复启动会立刻退出（避免开一堆）。
#
#  日志：guardian.log（同目录，超过 500 行自动截断）
# ============================================================

$ErrorActionPreference = "SilentlyContinue"

# ---- 单实例锁 ----
$mutex = New-Object System.Threading.Mutex($false, "Global\dsh-guardian-singleton")
if (-not $mutex.WaitOne(0)) {
  exit 0            # 已经有一个在跑
}

$tools   = $PSScriptRoot
$logPath = Join-Path $tools "guardian.log"
$dshExe  = "D:\DeepseeK\DeepSeek Harness.exe"
$adBat   = Join-Path $tools "dsh-link-autostart.bat"

function Log($msg) {
  $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $msg
  Add-Content -Path $logPath -Value $line -ErrorAction SilentlyContinue
  $c = @(Get-Content $logPath -ErrorAction SilentlyContinue)
  if ($c.Count -gt 500) { $c | Select-Object -Last 200 | Set-Content $logPath -Encoding UTF8 }
}

function Test-Dsh {
  @(Get-Process -Name "DeepSeek Harness" -ErrorAction SilentlyContinue).Count -gt 0
}

function Test-Link {
  $j = Get-CimInstance Win32_Process -Filter "Name='java.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -match "DshLink" }
  $null -ne $j
}

Log "guardian 启动（15 秒一轮，单实例）"

while ($true) {
  try {
    if (-not (Test-Dsh)) {
      if (Test-Path $dshExe) { Log "dsh 不在，启动它"; Start-Process -FilePath $dshExe; Start-Sleep 10 }
      else { Log "找不到 dsh: $dshExe" }
    }
    if (-not (Test-Link)) {
      if (Test-Path $adBat) { Log "dsh-link 不在，启动它"; & $adBat; Start-Sleep 6 }
    }
  } catch {
    Log "异常: $($_.Exception.Message)"
  }
  Start-Sleep -Seconds 15
}