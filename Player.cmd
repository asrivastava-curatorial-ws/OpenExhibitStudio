@echo off
rem Play an exhibit. Drop a project.oes.json or .oex on this file, or add --fullscreen / --kiosk.
setlocal
set "ROOT=%~dp0"
set "ENGINE=%ROOT%bin\godot.exe"
if defined OPENEXHIBIT_GODOT set "ENGINE=%OPENEXHIBIT_GODOT%"
if not exist "%ENGINE%" goto setup
if exist "%ROOT%app\project.godot" if not exist "%ROOT%app\.godot\imported" goto setup
goto run
:setup
if not exist "%ROOT%packaging\Setup-Windows.ps1" (
  echo The Godot engine is missing. Copy bin\godot.exe from a Studio installation.
  pause
  exit /b 1
)
echo First start: preparing OpenExhibit Player...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ROOT%packaging\Setup-Windows.ps1"
if errorlevel 1 (
  pause
  exit /b 1
)
:run
set "PROJECT="
if not "%~1"=="" if exist "%~1" (
  set PROJECT=--project "%~f1"
  shift
)
if exist "%ROOT%app\project.godot" (
  start "" "%ENGINE%" --path "%ROOT%app" res://player/player.tscn -- --examples "%ROOT%examples" %PROJECT% %1 %2 %3
) else (
  start "" "%ENGINE%" --main-pack "%ROOT%bin\player.pck" -- --examples "%ROOT%examples" %PROJECT% %1 %2 %3
)
