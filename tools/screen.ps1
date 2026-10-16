param(
  [Parameter(Position=0)]
  [string]$Action = "status"
)

# ============================================================
#  屏幕亮度控制（笔记本内屏，走 WMI）
#  用法:
#    screen.ps1 off      关到最暗 (0)
#    screen.ps1 on       调回最亮 (100)
#    screen.ps1 30       调到 30%
#    screen.ps1 status   查当前亮度
#    screen.ps1 toggle   亮/暗 来回切
# ============================================================

$ErrorActionPreference = "Stop"

function Get-Brightness {
  try {
    (Get-CimInstance -Namespace root/WMI -ClassName WmiMonitorBrightness).CurrentBrightness |
      Select-Object -First 1
  } catch { $null }
}

function Set-Brightness([int]$v) {
  if ($v -lt 0) { $v = 0 }
  if ($v -gt 100) { $v = 100 }
  $m = Get-CimInstance -Namespace root/WMI -ClassName WmiMonitorBrightnessMethods
  foreach ($inst in @($m)) {
    Invoke-CimMethod -InputObject $inst -MethodName WmiSetBrightness -Arguments @{
      Timeout    = [uint32]0
      Brightness = [byte]$v
    } | Out-Null
  }
  return $v
}

switch -Regex ($Action.ToLower()) {
  "^(status|s)$" {
    $cur = Get-Brightness
    if ($null -eq $cur) { Write-Output "不支持亮度调节"; exit 1 }
    Write-Output "当前亮度: $cur"
  }
  "^(off|dark|0)$" {
    Set-Brightness 0 | Out-Null
    Write-Output "已调到 0（最暗）"
  }
  "^(on|bright|100)$" {
    Set-Brightness 100 | Out-Null
    Write-Output "已调到 100（最亮）"
  }
  "^(dim)$" {
    Set-Brightness 15 | Out-Null
    Write-Output "已调到 15（微光）"
  }
  "^(toggle|t)$" {
    $cur = Get-Brightness
    if ($null -eq $cur) { Write-Output "不支持"; exit 1 }
    if ($cur -le 10) { Set-Brightness 100 | Out-Null; Write-Output "已调亮 (100)" }
    else { Set-Brightness 0 | Out-Null; Write-Output "已调暗 (0)" }
  }
  "^\d+$" {
    $v = [int]$Action
    Set-Brightness $v | Out-Null
    Write-Output "已调到 $v"
  }
  default {
    Write-Output "用法: screen.ps1 [off|on|dim|toggle|status|<0-100>]"
  }
}
