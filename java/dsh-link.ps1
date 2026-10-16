# dsh-link - start silently (no window). Called by start-silent.vbs
$ErrorActionPreference = "SilentlyContinue"
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path

# ---- locate java ----
# 1) DSH_LINK_JAVA env var   2) JAVA_HOME   3) PATH   4) common install dirs
$java = $null
if ($env:DSH_LINK_JAVA -and (Test-Path $env:DSH_LINK_JAVA)) { $java = $env:DSH_LINK_JAVA }
if (-not $java -and $env:JAVA_HOME -and (Test-Path "$env:JAVA_HOME\bin\java.exe")) { $java = "$env:JAVA_HOME\bin\java.exe" }
if (-not $java) { $java = (Get-Command java -ErrorAction SilentlyContinue | Select-Object -First 1).Source }
if (-not $java) {
  $cands = @(
    "$env:ProgramFiles\Android\Android Studio\jbr\bin\java.exe",
    "$env:LOCALAPPDATA\Programs\Android Studio\jbr\bin\java.exe",
    "D:\Android studio\jbr\bin\java.exe",
    "$env:ProgramFiles\Java\jdk-21\bin\java.exe",
    "$env:ProgramFiles\Java\jdk-17\bin\java.exe"
  )
  foreach ($c in $cands) { if (Test-Path $c) { $java = $c; break } }
}
if (-not $java) { exit 1 }
$javaHome = Split-Path (Split-Path $java)
$javac = Join-Path $javaHome "bin\javac.exe"

# ---- auto compile if needed ----
if (-not (Test-Path (Join-Path $dir "DshLink.class"))) {
  if (Test-Path $javac) {
    Push-Location $dir
    & $javac -encoding UTF-8 DshLink.java
    Pop-Location
  } else { exit 2 }
}

# ---- locate adb ----
$adb = (Get-Command adb -ErrorAction SilentlyContinue | Select-Object -First 1).Source
if (-not $adb) {
  $c = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
  if (Test-Path $c) { $adb = $c }
}

# ---- already running? ----
$running = Get-CimInstance Win32_Process -Filter "Name='java.exe'" |
  Where-Object { $_.CommandLine -match "DshLink" }
if ($running) { exit 0 }

# ---- launch hidden ----
$argList = @("-Dfile.encoding=UTF-8", "-cp", $dir, "DshLink", "23554", "19387")
if ($adb) { $argList += $adb }
$p = Start-Process -FilePath $java -ArgumentList $argList -WorkingDirectory $dir -WindowStyle Hidden -PassThru
$p.Id | Out-File (Join-Path $dir ".dsh-link.pid") -Encoding ASCII
