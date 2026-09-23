@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Run-V6-400M-NoCapture.ps1" -DurationSeconds 60
pause
