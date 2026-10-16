@echo off
REM ============================================================
REM  dam-on.bat  -  Restore "Desktop Activity Moderator" (DAM)
REM  undoes dam-off.bat (sets the kernel driver back to system-start)
REM  Needs a REBOOT.
REM ============================================================

net session >nul 2>&1
if %errorlevel% neq 0 (
  echo.
  echo Requesting administrator privileges... please click "Yes" on the UAC dialog.
  echo.
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)

echo ============================================================
echo   Restoring Desktop Activity Moderator (DAM)
echo ============================================================
echo.

reg add "HKLM\SYSTEM\CurrentControlSet\Services\dam" /v Start /t REG_DWORD /d 1 /f
echo.
reg query "HKLM\SYSTEM\CurrentControlSet\Services\dam" /v Start

echo.
echo DONE. Please REBOOT.
echo.
pause
