@echo off
REM ============================================================
REM  dsh-link  (Python version)
REM  Local proxy 127.0.0.1:23554  -->  dsh GUI 127.0.0.1:19387
REM ============================================================
cd /d "%~dp0"

set "PY="
for /f "delims=" %%i in ('where python 2^>nul') do if not defined PY set "PY=%%i"
if not defined PY if exist "%LOCALAPPDATA%\Programs\Python\Python312\python.exe" set "PY=%LOCALAPPDATA%\Programs\Python\Python312\python.exe"
if not defined PY if exist "%LOCALAPPDATA%\Programs\Python\Python311\python.exe" set "PY=%LOCALAPPDATA%\Programs\Python\Python311\python.exe"
if not defined PY if exist "%ProgramFiles%\Python312\python.exe" set "PY=%ProgramFiles%\Python312\python.exe"
if not defined PY (
  echo [ERROR] python.exe not found. Install Python 3.8+ or add it to PATH.
  pause
  exit /b 1
)

set "ADB="
for /f "delims=" %%i in ('where adb 2^>nul') do if not defined ADB set "ADB=%%i"
if not defined ADB if exist "%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe" set "ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe"

echo ============================================================
echo   dsh-link (Python)
echo   python : %PY%
echo   adb    : %ADB%
echo ============================================================
echo.

if defined ADB (
  echo [1/2] adb reverse tcp:19387 -^> tcp:23554
  "%ADB%" reverse tcp:19387 tcp:23554
) else (
  echo [1/2] adb not found, skip adb reverse
)
echo.
echo [2/2] starting proxy... (close this window to stop)
echo.
"%PY%" dsh_proxy.py 127.0.0.1 23554 127.0.0.1 19387
echo.
pause
