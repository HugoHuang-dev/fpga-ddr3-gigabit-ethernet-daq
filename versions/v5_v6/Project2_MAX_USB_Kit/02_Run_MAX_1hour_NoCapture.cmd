@echo off
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Run-MAX-NoCapture.ps1" -DurationSeconds 3600
echo.
echo One-hour MAX test finished. Keep this window and the newest results folder.
pause
