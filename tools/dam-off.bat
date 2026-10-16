@echo off
REM ============================================================
REM  dam-off.bat  -  Disable "Desktop Activity Moderator" (DAM)
REM
REM  Why:
REM    On Modern Standby (S0) laptops, when the screen turns off,
REM    the DAM kernel driver (dam.sys) FREEZES all Win32 desktop
REM    apps. That kills remote-access helpers (dsh-link, adb, etc).
REM
REM    Disabling DAM -> apps keep running during S0
REM                  -> closing the screen no longer kills the link.
REM
REM  Note: dam is a KERNEL DRIVER, so this needs a REBOOT.
REM  Revert: run dam-on.bat
REM ============================================================

REM ---- self-elevate to Administrator ----
net session >nul 2>&1
if %errorlevel% neq 0 (
  echo.
  echo Requesting administrator privileges... please click "Yes" on the UAC dialog.
  echo.
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)

echo ============================================================
echo   Disabling Desktop Activity Moderator (DAM)
echo ============================================================
echo.

echo [1/3] Backup current value ...
for /f "tokens=3" %%a in ('reg query "HKLM\SYSTEM\CurrentControlSet\Services\dam" /v Start 2^>nul ^| findstr /i "Start"') do set OLDVAL=%%a
echo   old Start = %OLDVAL%

echo [2/3] Set Start = 4 (disabled) ...
reg add "HKLM\SYSTEM\CurrentControlSet\Services\dam" /v Start /t REG_DWORD /d 4 /f
if %errorlevel% neq 0 (
  echo   FAILED.
  pause
  exit /b 1
)
echo   OK.

echo [3/3] Verify ...
reg query "HKLM\SYSTEM\CurrentControlSet\Services\dam" /v Start

echo.
echo ============================================================
echo   DONE.  Please REBOOT now.
echo.
echo   After reboot:
echo     - Screen can be turned off / blacked out
echo     - dsh-link + adb keep running
echo     - your phone link stays alive
echo.
echo   To revert: run dam-on.bat
echo ============================================================
echo.
pause
