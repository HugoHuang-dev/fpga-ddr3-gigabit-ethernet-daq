@echo off
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Run-315M-NoCapture.ps1"
echo.
echo Test script finished. Keep this window and the newest results folder.
pause
