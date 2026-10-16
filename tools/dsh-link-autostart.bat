@echo off
REM ============================================================
REM  dsh-link-autostart.bat  -  Startup launcher
REM    1. start DeepSeek Harness (dsh) if not running
REM    2. start dsh-link proxy
REM ============================================================
setlocal
cd /d "%~dp0"

set "DSH=D:\DeepseeK\DeepSeek Harness.exe"

REM ---- locate java ----
set "JAVA="
for /f "delims=" %%i in ('where java 2^>nul') do if not defined JAVA set "JAVA=%%i"
if not defined JAVA if exist "D:\Android studio\jbr\bin\java.exe" set "JAVA=D:\Android studio\jbr\bin\java.exe"
if not defined JAVA if exist "%ProgramFiles%\Android\Android Studio\jbr\bin\java.exe" set "JAVA=%ProgramFiles%\Android\Android Studio\jbr\bin\java.exe"
if not defined JAVA if exist "%LOCALAPPDATA%\Programs\Android Studio\jbr\bin\java.exe" set "JAVA=%LOCALAPPDATA%\Programs\Android Studio\jbr\bin\java.exe"
if not defined JAVA if exist "%ProgramFiles%\Java\jdk-21\bin\java.exe" set "JAVA=%ProgramFiles%\Java\jdk-21\bin\java.exe"

REM ---- locate adb ----
set "ADB="
for /f "delims=" %%i in ('where adb 2^>nul') do if not defined ADB set "ADB=%%i"
if not defined ADB if exist "%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe" set "ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe"

REM ---- 1) dsh ----
if exist "%DSH%" (
  tasklist /fi "imagename eq DeepSeek Harness.exe" 2>nul | find /i "DeepSeek" >nul
  if errorlevel 1 start "" "%DSH%"
)

REM ---- 2) dsh-link ----
if defined JAVA (
  cd /d "%~dp0..\java"
  if not exist "DshLink.class" (
    for %%d in ("%JAVA%") do set "JAVAC=%%~dpdjavac.exe"
    if exist "%JAVAC%" "%JAVAC%" --release 17 -encoding UTF-8 -d . DshLink.java
  )
  start "" /b "%JAVA%" -Dfile.encoding=UTF-8 -cp . DshLink 23554 19387 "%ADB%"
)

cd /d "%~dp0"

endlocal
exit /b 0