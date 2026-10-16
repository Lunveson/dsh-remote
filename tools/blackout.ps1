param(
  [string]$Action = "on"
)

# ============================================================
#  blackout —— "假关屏"（全屏黑窗口覆盖）
#
#  ★为什么不真关屏★
#    现代待机(S0)的机器上，"关闭显示器"本身就是进入待机的触发条件，
#    系统会冻结所有应用 → 远程链路断。
#    （Todesk 的"隐私屏"就是这么做的：盖一个黑窗口，不真的关屏。）
#
#  做法：开一个无边框、置顶、全屏、纯黑的窗口盖住屏幕。
#    · 系统照常运行（就是一个普通窗口）
#    · 屏幕上什么都看不到
#    · 关掉进程就恢复
#
#  用法:
#    blackout.ps1 on     开黑屏
#    blackout.ps1 off    关黑屏
#    blackout.ps1 status 查状态
# ============================================================

$ErrorActionPreference = "SilentlyContinue"
$pidFile = Join-Path $PSScriptRoot ".blackout.pid"

function Stop-Blackout {
  if (Test-Path $pidFile) {
    $oldPid = (Get-Content $pidFile -ErrorAction SilentlyContinue | Select-Object -First 1)
    if ($oldPid) { Stop-Process -Id $oldPid -Force -ErrorAction SilentlyContinue }
    Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
  }
  # 兜底：按命令行匹配
  Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match "blackout" -and $_.CommandLine -match "run" } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
}

function Start-Blackout {
  Stop-Blackout
  $inner = Join-Path $PSScriptRoot "blackout-run.ps1"
  if (-not (Test-Path $inner)) {
    Write-Output "缺少 blackout-run.ps1"
    return
  }
  $p = Start-Process -FilePath "powershell" `
    -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-File", $inner) `
    -WindowStyle Hidden -PassThru
  $p.Id | Out-File $pidFile -Encoding ASCII
  Write-Output "黑屏已开（PID $($p.Id)）—— 屏幕全黑，系统照常运行"
}

switch -Regex ($Action.ToLower()) {
  "^(on|black|start)$"  { Start-Blackout }
  "^(off|wake|stop)$"   { Stop-Blackout; Write-Output "黑屏已关，恢复显示" }
  "^(status|s)$"        {
    if (Test-Path $pidFile) {
      $q = Get-Content $pidFile | Select-Object -First 1
      $proc = Get-Process -Id $q -ErrorAction SilentlyContinue
      Write-Output $(if ($proc) { "黑屏中（PID $q）" } else { "黑屏已退出" })
    } else { Write-Output "未开黑屏" }
  }
  default { Write-Output "用法: blackout.ps1 [on|off|status]" }
}
