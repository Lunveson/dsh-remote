param(
  [switch]$SkipBuild,        # 跳过编译，直接装现有 APK
  [int]$WaitSeconds = 12,    # 装完等多久再自检
  [switch]$KeepBackup        # 保留备份（默认保留 1 个）
)

# ============================================================
#  deploy-apk.ps1 —— ★带自检 + 自动回滚★的 APK 部署
#
#  流程：
#    ①（可选）编译
#    ② 备份当前 APK 和它的版本信息
#    ③ 安装新 APK
#    ④ 启动 App，等 N 秒
#    ⑤ ★自检★：进程在不在 / 前台是不是它 / logcat 有没有崩溃
#    ⑥ 自检不过 → ★自动回滚到备份★
#    ⑦ 报告结果（含"网页兜底"提示）
#
#  用法：
#    powershell -File deploy-apk.ps1                # 编译+装+自检
#    powershell -File deploy-apk.ps1 -SkipBuild     # 只装现有的
# ============================================================

$ErrorActionPreference = "SilentlyContinue"

$root   = Split-Path -Parent $PSScriptRoot
$dir    = Join-Path $root "android"
$apk    = Join-Path $dir "app\build\outputs\apk\debug\app-debug.apk"
$bakDir = Join-Path $PSScriptRoot "apk-backup"
$bakApk = Join-Path $bakDir "app-debug.last-good.apk"
$bakTxt = Join-Path $bakDir "last-good.txt"
$gradle = "D:\gradle-8.13-bin\gradle-8.13\bin\gradle.bat"
$pkg    = "com.rptchat.dshremote"
$act    = "$pkg/.MainActivity"
$webUrl = "http://127.0.0.1:19387"

function Say($m, $c = "Gray") { Write-Host $m -ForegroundColor $c }

# ---- adb ----
$adb = (Get-Command adb -ErrorAction SilentlyContinue | Select-Object -First 1).Source
if (-not $adb) {
  $c = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
  if (Test-Path $c) { $adb = $c }
}
if (-not $adb) { Say "[X] 找不到 adb" "Red"; exit 1 }

$dev = (& $adb devices 2>&1 | Select-String "device$")
if (-not $dev) { Say "[X] 没有 adb 设备连着" "Red"; exit 1 }

New-Item -ItemType Directory -Path $bakDir -Force | Out-Null

# ==================== ① 编译 ====================
if (-not $SkipBuild) {
  Say "[1/6] 编译 ..." "Cyan"
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $build = & $gradle -p $dir assembleDebug 2>&1
  $failed = $build | Select-String "FAILED|error:"
  if ($failed) {
    Say "  [X] 编译失败：" "Red"
    $failed | Select-Object -First 5 | ForEach-Object { Say "    $_" "Red" }
    Say "  编译没过，什么都没装（安全）" "Yellow"
    exit 1
  }
  Say "  编译成功（$([math]::Round($sw.Elapsed.TotalSeconds,1)) 秒）" "Green"
} else {
  Say "[1/6] 跳过编译" "DarkGray"
}

if (-not (Test-Path $apk)) { Say "[X] 找不到 APK: $apk" "Red"; exit 1 }
$newSize = [math]::Round((Get-Item $apk).Length/1KB, 0)
Say "  APK: $newSize KB" "Gray"

# ==================== ② 备份当前版本 ====================
Say "[2/6] 备份当前版本 ..." "Cyan"
$cur = & $adb shell pm path $pkg 2>&1 | Select-String "package:"
if ($cur) {
  $remote = ($cur -replace "package:", "").Trim()
  & $adb pull $remote $bakApk 2>&1 | Out-Null
  if (Test-Path $bakApk) {
    $verName = (& $adb shell dumpsys package $pkg 2>&1 | Select-String "versionName=" | Select-Object -First 1)
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  versionName=$verName  size=$([math]::Round((Get-Item $bakApk).Length/1KB,0))KB" |
      Set-Content $bakTxt -Encoding UTF8
    Say "  已备份到 apk-backup\app-debug.last-good.apk ($([math]::Round((Get-Item $bakApk).Length/1KB,0)) KB)" "Green"
  } else {
    Say "  拉取失败（继续，但这次没有回滚点）" "Yellow"
  }
} else {
  Say "  手机上还没装过（首次安装，没有回滚点）" "Yellow"
}

# ==================== ③ 安装 ====================
Say "[3/6] 安装新 APK ..." "Cyan"
$inst = & $adb install -r $apk 2>&1 | Select-Object -Last 1
Say "  $inst" $(if ($inst -match "Success") { "Green" } else { "Red" })
if ($inst -notmatch "Success") {
  Say "  安装失败 → 立刻回滚" "Yellow"
  if (Test-Path $bakApk) { & $adb install -r $bakApk 2>&1 | Select-Object -Last 1 | ForEach-Object { Say "  回滚: $_" "Yellow" } }
  exit 1
}

# ==================== ④ 启动 + 等 ====================
Say "[4/6] 启动 App，等 $WaitSeconds 秒 ..." "Cyan"
& $adb shell am force-stop $pkg 2>&1 | Out-Null
Start-Sleep 1
& $adb logcat -c 2>&1 | Out-Null          # 清日志，方便看新日志
& $adb shell am start -n $act 2>&1 | Out-Null
Start-Sleep $WaitSeconds

# ==================== ⑤ 自检 ====================
Say "[5/6] 自检 ..." "Cyan"

$ok = $true
$reasons = @()

# (a) 进程在不在
$pidOut = & $adb shell pidof $pkg 2>&1
if ($pidOut -and $pidOut.Trim()) {
  Say "  ✓ 进程在（pid $($pidOut.Trim())）" "Green"
} else {
  $ok = $false; $reasons += "进程不在（可能崩了）"
  Say "  ✗ 进程不在" "Red"
}

# (b) 前台是不是它
$top = & $adb shell dumpsys activity activities 2>&1 | Select-String "topResumedActivity" | Select-Object -First 1
if ($top -match [regex]::Escape($pkg)) {
  Say "  ✓ 前台是它" "Green"
} else {
  $ok = $false; $reasons += "前台不是它（可能闪退了）"
  Say "  ✗ 前台不是它：$top" "Red"
}

# (c) 有没有崩溃
$crash = & $adb logcat -d 2>&1 | Select-String "FATAL EXCEPTION|AndroidRuntime.*$pkg" | Select-Object -First 3
if ($crash) {
  $ok = $false; $reasons += "logcat 里有崩溃"
  Say "  ✗ 发现崩溃日志：" "Red"
  $crash | ForEach-Object { Say "      $_" "Red" }
} else {
  Say "  ✓ 没有崩溃日志" "Green"
}

# ==================== ⑥ 结果 / 回滚 ====================
Say "[6/6] 结果 ..." "Cyan"
if ($ok) {
  Say ""
  Say "★部署成功，自检全过★" "Green"
  Say "  新版本已在手机上运行。备份保留在 apk-backup\（下次还会覆盖）" "DarkGray"
} else {
  Say ""
  Say "★★自检没通过，开始自动回滚★★" "Yellow"
  $reasons | ForEach-Object { Say "  原因: $_" "Yellow" }

  if (Test-Path $bakApk) {
    $rb = & $adb install -r $bakApk 2>&1 | Select-Object -Last 1
    Say "  回滚安装: $rb" $(if ($rb -match "Success") { "Green" } else { "Red" })
    if ($rb -match "Success") {
      & $adb shell am start -n $act 2>&1 | Out-Null
      Say "  已启动回滚后的版本" "Green"
    } else {
      Say "  [X] 回滚也失败了 —— 用网页兜底" "Red"
    }
  } else {
    Say "  没有备份可回滚（首次安装）" "Yellow"
  }

  Say ""
  Say "★网页兜底★：手机上用浏览器打开 $webUrl" "Cyan"
  Say "   （这条链路走 adb reverse，不依赖 App）" "DarkGray"
}

Say ""
Say "本次日志：apk-backup\ 目录下有 last-good.txt（记录回滚点信息）" "DarkGray"
