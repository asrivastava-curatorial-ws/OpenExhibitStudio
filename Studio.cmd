@echo off
rem Start OpenExhibit Studio. Drop a project.oes.json or .oex on this file to open it.
setlocal
set "ROOT=%~dp0"
set "ENGINE=%ROOT%bin\godot.exe"
if defined OPENEXHIBIT_GODOT set "ENGINE=%OPENEXHIBIT_GODOT%"
if not exist "%ENGINE%" goto setup
if exist "%ROOT%app\project.godot" if not exist "%ROOT%app\.godot\imported" goto setup
goto run
:setup
echo First start: preparing OpenExhibit (downloads the Godot engine once)...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ROOT%packaging\Setup-Windows.ps1"
if errorlevel 1 (
  pause
  exit /b 1
)
:run
set "PROJECT="
if not "%~1"=="" if exist "%~1" set PROJECT=--project "%~f1"
if exist "%ROOT%app\project.godot" (
  start "" "%ENGINE%" --path "%ROOT%app" -- --examples "%ROOT%examples" %PROJECT%
) else (
  start "" "%ENGINE%" --main-pack "%ROOT%bin\studio.pck" -- --examples "%ROOT%examples" %PROJECT%
)
