param(
  [Parameter(Position=0)]
  [string]$Action = "status"
)

# ============================================================
#  屏幕控制（笔记本）
#    status           查当前亮度
#    off / on         亮度 0 / 100
#    <0-100>          调到指定亮度
#    black            关显示器（背光也关，全黑）
#    wake             唤醒显示器
#    lock             关显示器 + 锁屏（全黑 + 要密码）
#
#  ★修复记录★
#   原来用 SendMessage(HWND_BROADCAST) 关屏 —— 它是【同步】的，
#   会被无响应的窗口卡死（实测卡了两分钟没返回）。
#   改用 SendMessageTimeout + SMTO_ABORTIFHUNG + 1 秒超时。
# ============================================================

$ErrorActionPreference = "SilentlyContinue"

if (-not ("Native.Scr" -as [type])) {
  Add-Type -Namespace Native -Name Scr -MemberDefinition @'
[DllImport("user32.dll", SetLastError = true)]
public static extern System.IntPtr SendMessageTimeout(
    System.IntPtr hWnd, uint Msg, System.IntPtr wParam, System.IntPtr lParam,
    uint fuFlags, uint uTimeout, out System.IntPtr lpdwResult);

[DllImport("user32.dll")]
public static extern bool SetCursorPos(int X, int Y);

[DllImport("user32.dll")]
public static extern bool LockWorkStation();
'@
}

$HWND_BROADCAST   = [IntPtr]0xFFFF
$WM_SYSCOMMAND    = [uint32]0x0112
$SC_MONITORPOWER  = [IntPtr]0xF170
$MONITOR_OFF      = [IntPtr]2
$MONITOR_ON       = [IntPtr](-1)
$SMTO_ABORTIFHUNG = [uint32]2

function Get-Brightness {
  (Get-CimInstance -Namespace root/WMI -ClassName WmiMonitorBrightness).CurrentBrightness |
    Select-Object -First 1
}

function Set-Brightness([int]$v) {
  if ($v -lt 0) { $v = 0 }; if ($v -gt 100) { $v = 100 }
  foreach ($inst in @(Get-CimInstance -Namespace root/WMI -ClassName WmiMonitorBrightnessMethods)) {
    Invoke-CimMethod -InputObject $inst -MethodName WmiSetBrightness -Arguments @{
      Timeout = [uint32]0; Brightness = [byte]$v
    } | Out-Null
  }
  return $v
}

# ★带超时的关/开屏（永不卡死）★
function Set-Monitor([IntPtr]$mode) {
  $out = [IntPtr]::Zero
  [void][Native.Scr]::SendMessageTimeout($HWND_BROADCAST, $WM_SYSCOMMAND,
    $SC_MONITORPOWER, $mode, $SMTO_ABORTIFHUNG, [uint32]1000, [ref]$out)
}

# 唤醒：鼠标微动（比 SendMessage 更可靠）
function Wake-Screen {
  try {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
    $p = [System.Windows.Forms.Cursor]::Position
    [void][Native.Scr]::SetCursorPos($p.X + 1, $p.Y)
    Start-Sleep -Milliseconds 100
    [void][Native.Scr]::SetCursorPos($p.X, $p.Y)
  } catch { }
  Set-Monitor $MONITOR_ON
}

switch -Regex ($Action.ToLower()) {
  "^(status|s)$"        { Write-Output "亮度: $(Get-Brightness)" }
  "^(off|dark)$"        { Write-Output "亮度 -> $(Set-Brightness 0)" }
  "^(on|bright)$"       { Write-Output "亮度 -> $(Set-Brightness 100)" }
  "^(black|screenoff)$" { Set-Monitor $MONITOR_OFF; Write-Output "显示器已关（全黑）" }
  "^(wake|screenon)$"   { Wake-Screen;             Write-Output "显示器已唤醒" }
  "^(lock)$"            { Set-Monitor $MONITOR_OFF
                          Start-Sleep -Milliseconds 500
                          [void][Native.Scr]::LockWorkStation()
                          Write-Output "已锁屏（全黑 + 要密码）" }
  "^\d+$"               { Write-Output "亮度 -> $(Set-Brightness ([int]$Action))" }
  default               { Write-Output "用法: display.ps1 [status|off|on|<0-100>|black|wake|lock]" }
}
