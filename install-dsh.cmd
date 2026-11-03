@echo off
rem Lanzador alternativo (sin .exe): ejecuta el script PowerShell directamente.
rem Uso:  install-dsh.cmd  [ -Mode Install|Update|Uninstall ]  [ -SkipNode ]
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0installer\install-dsh.ps1" %*
if errorlevel 1 pause
exit /b %errorlevel%
