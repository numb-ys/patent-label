@echo off
setlocal
echo Open a drawing in AutoCAD 2014 before installing.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install2014.ps1" -Action Install
if errorlevel 1 (
  echo Installation did not finish. See the error above and README-2014.txt.
) else (
  echo Done. Restart AutoCAD 2014, then type BH.
)
pause
