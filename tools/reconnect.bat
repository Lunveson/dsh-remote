@echo off
REM ============================================================
REM  Reconnect after reboot - double-click this file
REM  (calls tools\reconnect.ps1)
REM ============================================================
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0reconnect.ps1"
echo.
pause
