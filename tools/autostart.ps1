param(
  [switch]$Remove
)

# ============================================================
#  autostart.ps1 —— 管理"开机自动启动 dsh-link"
#
#  安装：在【启动】文件夹放一个快捷方式，指向 java\start-silent.vbs
#        （用户登录后自动运行，无窗口）
#  卸载：删掉那个快捷方式
#
#  用法：
#    powershell -File autostart.ps1           安装
#    powershell -File autostart.ps1 -Remove   卸载
#    powershell -File autostart.ps1 -Status   查看
# ============================================================

$ErrorActionPreference = "Stop"

$root      = Split-Path -Parent $PSScriptRoot
$vbs       = Join-Path $root "java\start-silent.vbs"
$startup   = [Environment]::GetFolderPath("Startup")
$lnkPath   = Join-Path $startup "dsh-link.lnk"
$wscript   = Join-Path $env:SystemRoot "System32\wscript.exe"

function Show-Status {
  Write-Host "启动文件夹: $startup"
  if (Test-Path $lnkPath) {
    Write-Host "自启状态  : ★已安装★" -ForegroundColor Green
    $sh = New-Object -ComObject WScript.Shell
    $l = $sh.CreateShortcut($lnkPath)
    Write-Host "  目标: $($l.TargetPath)"
    Write-Host "  参数: $($l.Arguments)"
  } else {
    Write-Host "自启状态  : 未安装" -ForegroundColor Yellow
  }
}

if ($args -contains "-Status") { Show-Status; exit 0 }

if ($Remove) {
  if (Test-Path $lnkPath) { Remove-Item $lnkPath -Force; Write-Host "已卸载开机自启" -ForegroundColor Green }
  else { Write-Host "本来就没装" -ForegroundColor Yellow }
  exit 0
}

# ---- 安装 ----
if (-not (Test-Path $vbs)) {
  Write-Host "[X] 找不到 $vbs" -ForegroundColor Red
  exit 1
}

$sh = New-Object -ComObject WScript.Shell
$l = $sh.CreateShortcut($lnkPath)
$l.TargetPath       = $wscript
$l.Arguments        = '"' + $vbs + '"'
$l.WorkingDirectory = Join-Path $root "java"
$l.WindowStyle      = 7            # 最小化（vbs 本身不显示窗口）
$l.Description      = "dsh-link - phone access to DSH (auto start)"
$l.Save()

Write-Host "★已安装开机自启★" -ForegroundColor Green
Show-Status
