@echo off
setlocal
echo Open a drawing in AutoCAD 2019 before installing.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install2019.ps1" -Action Install
if errorlevel 1 (
  echo Installation did not finish. See the error above and README-2019.txt.
) else (
  echo Done. Restart AutoCAD 2019, then type BH.
)
pause
