@echo off
setlocal
echo Open a drawing in AutoCAD 2019 before uninstalling.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install2019.ps1" -Action Uninstall
pause
