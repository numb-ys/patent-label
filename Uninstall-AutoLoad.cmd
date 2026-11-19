@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\install-autoload.ps1" -Action Uninstall
pause
