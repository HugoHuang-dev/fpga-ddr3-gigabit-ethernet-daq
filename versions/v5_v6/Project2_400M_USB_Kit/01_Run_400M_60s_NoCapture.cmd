@echo off
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Run-400M-NoCapture.ps1" -DurationSeconds 60
echo.
echo 400M test finished. Keep this window and the newest results folder.
pause
