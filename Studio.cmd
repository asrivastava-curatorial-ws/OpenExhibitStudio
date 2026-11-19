@echo off
setlocal
set "ROOT=%~dp0"
set "PACKDIR=%ROOT%bin"
if exist "%ROOT%bin\windows\studio.pck" set "PACKDIR=%ROOT%bin\windows"
set "ENGINE=%PACKDIR%\godot.exe"
if defined OPENEXHIBIT_GODOT set "ENGINE=%OPENEXHIBIT_GODOT%"
if not exist "%ENGINE%" (
  echo Run Setup-Windows.cmd first or set OPENEXHIBIT_GODOT to Godot 4.6.3.
  pause
  exit /b 1
)
start "" "%ENGINE%" --main-pack "%PACKDIR%\studio.pck" -- --examples "%ROOT%examples" %*
