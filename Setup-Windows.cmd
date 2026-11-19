@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0packaging\Install-Windows.ps1" %*
if errorlevel 1 pause
