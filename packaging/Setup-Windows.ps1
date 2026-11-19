# OpenExhibit Studio — one-step setup for Windows 10/11 (x64). Run via Setup-Windows.cmd.
#
#   Setup-Windows.cmd               download the engine (once), prepare the app
#   Setup-Windows.cmd -Shortcuts    also add Start-menu and desktop shortcuts
#   Setup-Windows.cmd -Hardware     also create .venv with pyserial + paho-mqtt
#   Setup-Windows.cmd -Offline      use files already copied into .\downloads
#   Setup-Windows.cmd -Engine C:\path\Godot_v4.7.1-stable_win64.exe   use an engine you already have
#
# The official Godot archive is verified against a pinned SHA-512 before use. Everything stays
# inside this folder except the optional shortcuts.
[CmdletBinding()]
param([switch]$Offline, [switch]$Hardware, [switch]$Shortcuts, [string]$Engine)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # Invoke-WebRequest is much faster without the progress bar
$Root = Split-Path -Parent $PSScriptRoot
$Version = if ($env:OPENEXHIBIT_GODOT_VERSION) { $env:OPENEXHIBIT_GODOT_VERSION } else { '4.7.1' }
$Zip = "Godot_v$Version-stable_win64.exe.zip"
$Release = "https://github.com/godotengine/godot/releases/download/$Version-stable"
$Pinned = @{
  'Godot_v4.7.1-stable_win64.exe.zip' = 'a6b02c527c18ba9936e63562032701432b2dc57d98d6483ceaccb00fe14af16af5773ae8a55e7b4d614edf121c4d9e420d870f804edb1dac16362298a01ce6c4'
  'Godot_v4.6.3-stable_win64.exe.zip' = 'd44ea7ef5bab754cacd49d581b6062836b2eea12a82e1d183aebfad9cd8c7db2bd82513337bd657d6d2d5c04d46239c0570b029faf1343e81e8a2fa7b85dd83b'
}
$Downloads = if ($env:OPENEXHIBIT_DOWNLOADS) { $env:OPENEXHIBIT_DOWNLOADS } else { Join-Path $Root 'downloads' }
$Bin = Join-Path $Root 'bin'
$GodotExe = Join-Path $Bin 'godot.exe'
$GodotConsole = Join-Path $Bin 'godot_console.exe'

function Say($m)  { Write-Host "> $m" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "OK $m" -ForegroundColor Green }
function Warn($m) { Write-Host "!  $m" -ForegroundColor Yellow }

function Get-EngineVersion($exe) {
  if (-not (Test-Path -LiteralPath $exe)) { return '' }
  try { return ((& $exe --headless --version 2>$null | Out-String).Trim() -split "`n")[0] } catch { return '' }
}

New-Item -ItemType Directory -Force -Path $Bin, $Downloads | Out-Null

# ------------------------------------------------------------------ engine
if ($Engine) {
  if (-not (Test-Path -LiteralPath $Engine -PathType Leaf)) { throw "Engine not found: $Engine" }
  Copy-Item -LiteralPath $Engine -Destination $GodotExe -Force
  $console = [IO.Path]::ChangeExtension($Engine, $null).TrimEnd('.') + '_console.exe'
  if (Test-Path -LiteralPath $console) { Copy-Item -LiteralPath $console -Destination $GodotConsole -Force }
  Ok "Using your engine $Engine"
} elseif ((Get-EngineVersion $(if (Test-Path $GodotConsole) { $GodotConsole } else { $GodotExe })) -like "$Version.stable*") {
  Ok "Engine already installed: Godot $Version"
} else {
  $zipPath = Join-Path $Downloads $Zip
  if (-not (Test-Path -LiteralPath $zipPath)) {
    if ($Offline) { throw "Offline mode: copy $Zip into $Downloads first ($Release/$Zip)" }
    Say "Downloading Godot $Version from github.com/godotengine ..."
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -UseBasicParsing -Uri "$Release/$Zip" -OutFile "$zipPath.part"
    Move-Item -LiteralPath "$zipPath.part" -Destination $zipPath -Force
  }
  $expected = $Pinned[$Zip]
  if (-not $expected) {
    $sums = Join-Path $Downloads "SHA512-SUMS-$Version.txt"
    if (-not (Test-Path -LiteralPath $sums)) {
      if ($Offline) { throw "Offline mode: also copy the release's SHA512-SUMS.txt as $sums" }
      Invoke-WebRequest -UseBasicParsing -Uri "$Release/SHA512-SUMS.txt" -OutFile $sums
    }
    $m = [regex]::Match((Get-Content -Raw -LiteralPath $sums), '(?im)^([0-9a-f]{128})\s+\*?' + [regex]::Escape($Zip) + '\s*$')
    if (-not $m.Success) { throw "No published checksum for $Zip" }
    $expected = $m.Groups[1].Value
  }
  $actual = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA512).Hash.ToLowerInvariant()
  if ($actual -ne $expected.ToLowerInvariant()) {
    Remove-Item -LiteralPath $zipPath -Force
    throw "Checksum mismatch for $Zip. The download was deleted; run setup again."
  }
  Ok "SHA-512 verified: $Zip"
  $tmp = Join-Path ([IO.Path]::GetTempPath()) ('openexhibit-' + [guid]::NewGuid().ToString('N'))
  try {
    Expand-Archive -LiteralPath $zipPath -DestinationPath $tmp -Force
    $gui = Get-ChildItem -LiteralPath $tmp -Filter '*_win64.exe' | Select-Object -First 1
    $con = Get-ChildItem -LiteralPath $tmp -Filter '*_win64_console.exe' | Select-Object -First 1
    if (-not $gui) { throw "Unexpected archive layout in $Zip" }
    Copy-Item -LiteralPath $gui.FullName -Destination $GodotExe -Force
    if ($con) { Copy-Item -LiteralPath $con.FullName -Destination $GodotConsole -Force }
  } finally { if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force } }
  Ok "Installed Godot $Version in bin\"
}
# The console wrapper waits for completion and prints output; the GUI exe returns immediately.
$Runner = if (Test-Path -LiteralPath $GodotConsole) { $GodotConsole } else { $GodotExe }
Set-Content -LiteralPath (Join-Path $Bin 'ENGINE_VERSION') -Value (Get-EngineVersion $Runner)

# ------------------------------------------------------------------ import
Say 'Preparing the application (first run takes about half a minute) ...'
$log = Join-Path $Bin 'import.log'
& $Runner --headless --editor --import --path (Join-Path $Root 'app') *> $log
if (-not (Test-Path -LiteralPath (Join-Path $Root 'app\.godot\imported'))) { Get-Content -Tail 30 $log; throw "Godot could not import the app (see bin\import.log)" }
Ok 'App imported'

# ------------------------------------------------------------------ python
function Find-Python {
  foreach ($c in @(@('py', '-3'), @('python'), @('python3'))) {
    $cmd = Get-Command $c[0] -ErrorAction SilentlyContinue
    if (-not $cmd) { continue }
    if ($cmd.Source -like '*\WindowsApps\*') { continue }   # Microsoft Store alias, not a real interpreter
    $prefix = @($c | Select-Object -Skip 1)
    $probe = $prefix + @('-c', 'import sys;print(1 if sys.version_info>=(3,10) else 0)')
    try {
      if ((& $cmd.Source @probe 2>$null) -eq '1') {
        $found = @($cmd.Source) + $prefix
        return , $found   # keep it an array even with one element
      }
    } catch {}
  }
  return $null
}
$py = Find-Python
if (-not $py) {
  Warn 'Python 3.10+ was not found. Studio and Player work without it, but live audience quizzes and USB hardware need it.'
  if (Get-Command winget -ErrorAction SilentlyContinue) {
    $answer = Read-Host 'Install Python 3.12 now with winget? [Y/n]'
    if ($answer -notmatch '^[Nn]') {
      winget install -e --id Python.Python.3.12 --scope user --accept-package-agreements --accept-source-agreements
      $env:Path = [Environment]::GetEnvironmentVariable('Path', 'User') + ';' + [Environment]::GetEnvironmentVariable('Path', 'Machine')
      $py = Find-Python
    }
  } else { Warn 'Install it from https://www.python.org/downloads/windows/ (tick "Add python.exe to PATH").' }
}
if ($py) {
  Ok ('Python found: ' + ($py -join ' '))
  $exe = $py[0]; $pre = @($py | Select-Object -Skip 1)
  & $exe @pre (Join-Path $Root 'tools\build.py') --godot $Runner --platform windows --mode packs --out $Bin *> (Join-Path $Bin 'build.log')
  if ($LASTEXITCODE -eq 0) { Ok 'Standalone Player and Studio packs built (bin\*.pck)' } else { Warn 'Pack build failed (bin\build.log). Studio still runs from source.' }
  if ($Hardware) {
    Say 'Creating .venv for Arduino/ESP32 support ...'
    & $exe @pre -m venv (Join-Path $Root '.venv')
    $pip = Join-Path $Root '.venv\Scripts\pip.exe'
    $wheels = Join-Path $Downloads 'wheels'
    New-Item -ItemType Directory -Force -Path $wheels | Out-Null
    $req = Join-Path $Root 'gateway\requirements-optional.txt'
    if ($Offline) { & $pip install --no-index --find-links $wheels -r $req }
    else { & $pip download -q -d $wheels -r $req; & $pip install -q -r $req }
    Ok 'Hardware extras installed'
  }
}

# ------------------------------------------------------------------ shortcuts
if ($Shortcuts) {
  $shell = New-Object -ComObject WScript.Shell
  $menu = Join-Path ([Environment]::GetFolderPath('Programs')) 'OpenExhibit'
  New-Item -ItemType Directory -Force -Path $menu | Out-Null
  foreach ($role in 'Studio', 'Player') {
    foreach ($dir in @($menu, [Environment]::GetFolderPath('Desktop'))) {
      $lnk = $shell.CreateShortcut((Join-Path $dir "OpenExhibit $role.lnk"))
      $lnk.TargetPath = Join-Path $Root "$role.cmd"
      $lnk.WorkingDirectory = $Root
      $lnk.IconLocation = "$GodotExe,0"
      $lnk.WindowStyle = 7
      $lnk.Save()
    }
  }
  Ok 'Shortcuts added to the Start menu and desktop'
}
Write-Host ''
Ok 'Setup complete. Double-click Studio.cmd to start authoring, or Player.cmd to play an exhibit.'
