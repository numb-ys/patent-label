@echo off
setlocal
echo Open a drawing in AutoCAD 2014 before uninstalling.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install2014.ps1" -Action Uninstall
pause
