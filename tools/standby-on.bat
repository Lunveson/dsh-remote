@echo off
REM ============================================================
REM  standby-on.bat  -  Restore Modern Standby (S0)
REM  undoes standby-off.bat (removes PlatformAoAcOverride)
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
echo   Restoring Modern Standby (S0)
echo ============================================================
echo.

reg delete "HKLM\SYSTEM\CurrentControlSet\Control\Power" /v PlatformAoAcOverride /f
echo.
echo Current value (should say it does not exist):
reg query "HKLM\SYSTEM\CurrentControlSet\Control\Power" /v PlatformAoAcOverride

echo.
echo DONE. Please REBOOT.
echo.
pause
