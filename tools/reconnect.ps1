param(
  [string]$Phone = ""      # 可选：手动指定 手机IP:端口
)

# ============================================================
#  reconnect.ps1  ——  重启后一键重连（v2）
#
#  v1 的问题：挨个扫网段试 adb connect，每次失败都要等超时，很慢。
#  v2 的做法：直接重启 adb server，让它重新做 mDNS 自动发现
#             （手机开着"无线调试"时，adb 能自己找到它）。
#
#  做四件事：
#    ① 重启 adb server，等设备出现
#    ② 启动 dsh-link 代理
#    ③ 建立 adb reverse
#    ④ 报告结果
# ============================================================

$ErrorActionPreference = "SilentlyContinue"
$root  = Split-Path -Parent $PSScriptRoot
$javaD = Join-Path $root "java"

function Say($m, $c = "Gray") { Write-Host $m -ForegroundColor $c }

# ---- 找 adb ----
$adb = (Get-Command adb -ErrorAction SilentlyContinue | Select-Object -First 1).Source
if (-not $adb) {
  $c = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
  if (Test-Path $c) { $adb = $c }
}
if (-not $adb) { Say "[X] 找不到 adb" "Red"; exit 1 }

Say "=== dsh-remote 一键重连 ===" "Cyan"
Say "adb: $adb"
Say ""

function Get-Devices {
  $o = & $adb devices 2>&1 | Out-String
  @($o -split "`n" | Where-Object {
    $s = $_.Trim()
    $p = $s -split "\s+"
    $s -and -not $s.StartsWith("List of devices") -and -not $s.StartsWith("*") -and $p.Count -ge 2 -and $p[1] -eq "device"
  })
}

# ---- ① adb ----
Say "[1/4] 重启 adb server，重新发现手机 ..."
& $adb kill-server  2>&1 | Out-Null
Start-Sleep 2
& $adb start-server 2>&1 | Out-Null

$devices = @()
for ($i = 1; $i -le 10; $i++) {
  Start-Sleep 2
  $devices = Get-Devices
  if ($devices.Count -gt 0) { break }
  Write-Host "  ...等待中 ($i/10)"
}

if ($devices.Count -eq 0 -and $Phone) {
  Say "  手动指定了地址，尝试连接 $Phone"
  & $adb connect $Phone 2>&1 | Out-Null
  Start-Sleep 3
  $devices = Get-Devices
}

if ($devices.Count -eq 0) {
  Say "  [X] 没发现手机。" "Red"
  Say "      请确认手机上【开发者选项 → 无线调试】开着。" "Yellow"
  Say "      或者让手机开【个人热点】、电脑连上热点后再试。" "Yellow"
  exit 1
}

Say "  ★已连接:★" "Green"
$devices | ForEach-Object { Say "    $_" "Green" }
Say ""

# ---- ② dsh-link ----
Say "[2/4] 启动 dsh-link 代理 ..."
$running = Get-CimInstance Win32_Process -Filter "Name='java.exe'" | Where-Object { $_.CommandLine -match "DshLink" }
if ($running) {
  Say "  已经在跑 (PID $($running.ProcessId))" "Green"
} else {
  $vbs = Join-Path $javaD "start-silent.vbs"
  $ok = $false
  if (Test-Path $vbs) {
    & wscript.exe $vbs
    Start-Sleep 8
    $r2 = Get-CimInstance Win32_Process -Filter "Name='java.exe'" | Where-Object { $_.CommandLine -match "DshLink" }
    if ($r2) { Say "  已启动 (PID $($r2.ProcessId))" "Green"; $ok = $true }
  }
  if (-not $ok) {
    Say "  vbs 没起来，改用命令行直接启动 ..." "Yellow"
    $jav = (Get-Command java -ErrorAction SilentlyContinue | Select-Object -First 1).Source
    if (-not $jav -and (Test-Path "$env:ProgramFiles\Android\Android Studio\jbr\bin\java.exe")) {
      $jav = "$env:ProgramFiles\Android\Android Studio\jbr\bin\java.exe"
    }
    if (-not $jav -and (Test-Path "D:\Android studio\jbr\bin\java.exe")) {
      $jav = "D:\Android studio\jbr\bin\java.exe"
    }
    if ($jav) {
      Start-Process -FilePath $jav -ArgumentList @("-Dfile.encoding=UTF-8","-cp",$javaD,"DshLink","23554","19387",$adb) -WorkingDirectory $javaD -WindowStyle Hidden
      Start-Sleep 6
      $r3 = Get-CimInstance Win32_Process -Filter "Name='java.exe'" | Where-Object { $_.CommandLine -match "DshLink" }
      if ($r3) { Say "  已启动 (PID $($r3.ProcessId))" "Green" } else { Say "  [X] 仍然没起来，手动跑 java\start.bat 看报错" "Red" }
    } else {
      Say "  [X] 找不到 java" "Red"
    }
  }
}
Say ""

# ---- ③ adb reverse ----
Say "[3/4] 建立 adb reverse ..."
& $adb reverse tcp:19387 tcp:23554 2>&1 | Out-Null
$rev = & $adb reverse --list 2>&1
if ($rev) { $rev | ForEach-Object { Say "  $_" "Green" } }
else { Say "  reverse 没建上（dsh-link 每 3 秒会自己重试）" "Yellow" }
Say ""

# ---- ④ 完成 ----
Say "[4/4] 完成" "Cyan"
Say ""
Say "现在可以在手机上点【大肥鱼远程】了。" "White"
Say ""
Say "提示：dsh-link 每 3 秒自动检查设备 + reverse，断了会自己恢复。" "DarkGray"
