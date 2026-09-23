@echo off
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Run-MAX-NoCapture.ps1" -DurationSeconds 60
echo.
echo MAX unpaced test finished. Keep this window and the newest results folder.
pause
