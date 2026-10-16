@echo off
REM ============================================================
REM  dsh-link  (Java version)
REM  Local proxy 127.0.0.1:23554  -->  dsh GUI 127.0.0.1:19387
REM  Also maintains: adb reverse tcp:19387 -> tcp:23554
REM ============================================================
cd /d "%~dp0"

REM ---------- locate java ----------
set "JAVA="
for /f "delims=" %%i in ('where java 2^>nul') do if not defined JAVA set "JAVA=%%i"
if not defined JAVA if exist "%ProgramFiles%\Android\Android Studio\jbr\bin\java.exe" set "JAVA=%ProgramFiles%\Android\Android Studio\jbr\bin\java.exe"
if not defined JAVA if exist "%LOCALAPPDATA%\Programs\Android Studio\jbr\bin\java.exe" set "JAVA=%LOCALAPPDATA%\Programs\Android Studio\jbr\bin\java.exe"
if not defined JAVA if exist "%ProgramFiles%\Java\jdk-21\bin\java.exe" set "JAVA=%ProgramFiles%\Java\jdk-21\bin\java.exe"
if not defined JAVA if exist "%ProgramFiles%\Java\jdk-17\bin\java.exe" set "JAVA=%ProgramFiles%\Java\jdk-17\bin\java.exe"
if not defined JAVA if exist "%ProgramFiles%\Eclipse Adoptium\jdk-21*\bin\java.exe" set "JAVA=%ProgramFiles%\Eclipse Adoptium\jdk-21*\bin\java.exe"
if not defined JAVA (
  echo [ERROR] java.exe not found. Install a JDK 17+ or add java to PATH.
  pause
  exit /b 1
)
for %%d in ("%JAVA%") do set "JAVAC=%%~dpdjavac.exe"

REM ---------- locate adb ----------
set "ADB="
for /f "delims=" %%i in ('where adb 2^>nul') do if not defined ADB set "ADB=%%i"
if not defined ADB if exist "%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe" set "ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe"
if not defined ADB if exist "%USERPROFILE%\AppData\Local\Android\Sdk\platform-tools\adb.exe" set "ADB=%USERPROFILE%\AppData\Local\Android\Sdk\platform-tools\adb.exe"
if not defined ADB (
  echo [WARN] adb.exe not found - dsh-link will still run, but cannot set up adb reverse.
  echo        Install Android SDK platform-tools and put adb on PATH for phone access.
)

echo ============================================================
echo   dsh-link
echo   java : %JAVA%
echo   adb  : %ADB%
echo ============================================================
echo.

if not exist "DshLink.class" (
  if not exist "%JAVAC%" (
    echo [ERROR] DshLink.class missing, and javac.exe not found next to java.exe.
    echo         Compile it yourself:  javac -encoding UTF-8 DshLink.java
    pause
    exit /b 1
  )
  echo [build] compiling DshLink.java ...
  "%JAVAC%" -encoding UTF-8 -d . DshLink.java
  if errorlevel 1 ( pause & exit /b 1 )
)

echo Running... (close this window to stop)
echo.
"%JAVA%" -Dfile.encoding=UTF-8 -cp . DshLink 23554 19387 "%ADB%"
echo.
pause