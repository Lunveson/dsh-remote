param(
  [switch]$Once        # 只声明一次就退出（不常驻）
)

# ============================================================
#  keepawake —— 阻止系统进入"现代待机(S0)"，但★允许关显示器★
#
#  原理：SetThreadExecutionState(ES_CONTINUOUS | ES_SYSTEM_REQUIRED)
#    · ES_SYSTEM_REQUIRED  = 请求系统保持运行（不待机、不休眠）
#    · 不带 ES_DISPLAY_REQUIRED = 允许显示器关闭  ← ★关键★
#    · ES_CONTINUOUS       = 持续有效，直到本线程退出
#
#  ★这是线程级的★：本脚本里的 while 循环就是那个"一直活着的线程"。
#    关掉这个进程 → 系统恢复默认待机行为。
#
#  用法：
#    前台:  powershell -File keepawake.ps1
#    后台:  powershell -WindowStyle Hidden -File keepawake.ps1
#    一次:  powershell -File keepawake.ps1 -Once
# ============================================================

if (-not ("Native.Awake" -as [type])) {
  Add-Type -Namespace Native -Name Awake -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError = true)]
public static extern uint SetThreadExecutionState(uint esFlags);
'@
}

$ES_CONTINUOUS      = [uint32]0x80000000
$ES_SYSTEM_REQUIRED = [uint32]0x00000001
$flags = $ES_CONTINUOUS -bor $ES_SYSTEM_REQUIRED

[void][Native.Awake]::SetThreadExecutionState($flags)
Write-Output "[keepawake] 已启用：系统不待机，显示器仍可关闭"

if ($Once) { exit 0 }

# 常驻：每 30 秒重申一次（ES_CONTINUOUS 本身够用，这是保险）
while ($true) {
  [void][Native.Awake]::SetThreadExecutionState($flags)
  Start-Sleep -Seconds 30
}
