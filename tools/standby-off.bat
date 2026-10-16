@echo off
REM ============================================================
REM  standby-off.bat  -  Disable Modern Standby (S0)
REM
REM  Why:
REM    On S0 machines, turning the screen off puts the whole system
REM    into Modern Standby -> the WiFi adapter powers down
REM    -> wireless adb dies -> your phone link dies.
REM
REM    Disabling Modern Standby means "screen off" is just screen off:
REM    no S0, no WiFi power-down, adb stays alive.
REM
REM  Side effect:
REM    This machine has no S1/S2/S3 (S0 only), so after disabling S0
REM    the system can NOT sleep anymore (hibernate/shutdown still work).
REM    On AC power that is usually what you want.
REM
REM  Revert: run standby-on.bat
REM  Needs: Administrator + REBOOT
REM ============================================================

net session >nul 2>&1
if %errorlevel% neq 0 (
  echo.
  echo Requesting administrator privileges... click "Yes" on the UAC dialog.
  echo.
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)

echo ============================================================
echo   Disabling Modern Standby (S0)
echo ============================================================
echo.

echo [1/3] Write PlatformAoAcOverride = 0 ...
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Power" /v PlatformAoAcOverride /t REG_DWORD /d 0 /f
if %errorlevel% neq 0 (
  echo   FAILED.
  pause
  exit /b 1
)
echo   OK.

echo [2/3] Verify ...
reg query "HKLM\SYSTEM\CurrentControlSet\Control\Power" /v PlatformAoAcOverride

echo [3/3] Sleep states after change (will be accurate after reboot) ...
powercfg /a

echo.
echo ============================================================
echo   DONE.  Please REBOOT now.
echo.
echo   After reboot:
echo     - Turning the screen off will NOT put the system to sleep
echo     - WiFi stays up, wireless adb stays up
echo     - your phone link survives screen-off
echo.
echo   To revert: run standby-on.bat
echo ============================================================
echo.
pause
