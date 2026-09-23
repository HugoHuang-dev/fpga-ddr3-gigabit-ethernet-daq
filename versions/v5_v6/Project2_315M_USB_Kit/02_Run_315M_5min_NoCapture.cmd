@echo off
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Run-315M-NoCapture.ps1" -DurationSeconds 300
echo.
echo Five-minute test script finished. Keep this window and the newest results folder.
pause
