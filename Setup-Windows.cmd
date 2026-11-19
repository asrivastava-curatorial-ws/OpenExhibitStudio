@echo off
rem One-step Windows setup: downloads the Godot engine (SHA-512 verified) and prepares OpenExhibit.
rem Options: -Shortcuts  -Hardware  -Offline  -Engine C:\path\to\Godot_v4.7.1-stable_win64.exe
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0packaging\Setup-Windows.ps1" %*
if errorlevel 1 pause
