[CmdletBinding()]
param([string]$Engine, [switch]$PlayerOnly, [switch]$DownloadEngine, [string]$Destination)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$label=if($PlayerOnly){'OpenExhibit Player'}else{'OpenExhibit Studio'}
if(-not $Destination){$Destination=Join-Path $env:LOCALAPPDATA "Programs\$label"}
if(-not $Engine){
  $bundled=Join-Path $root 'bin\godot.exe'
  if(-not(Test-Path -LiteralPath $bundled)){$bundled=Join-Path $root 'bin\windows\godot.exe'}
  if(Test-Path -LiteralPath $bundled){$Engine=$bundled}
  else {
    $found=Get-Command godot.exe -ErrorAction SilentlyContinue
    if($found){$Engine=$found.Source}
  }
}
$temporaryEngine=$null
try {
if(-not $Engine){
  Add-Type -AssemblyName System.Windows.Forms
  if(-not $DownloadEngine){
    $choice=[System.Windows.Forms.MessageBox]::Show('Download the official Godot 4.6.3 engine now? Choose No to select an existing offline executable.','OpenExhibit Windows setup','YesNoCancel','Question')
    if($choice -eq 'Cancel'){return}
    $DownloadEngine=($choice -eq 'Yes')
  }
  if($DownloadEngine){
    $temporaryEngine=Join-Path ([IO.Path]::GetTempPath()) ('openexhibit-engine-'+[guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $temporaryEngine | Out-Null
    $file='Godot_v4.6.3-stable_win64.exe.zip'
    $release='https://github.com/godotengine/godot-builds/releases/download/4.6.3-stable'
    [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
    $zip=Join-Path $temporaryEngine $file
    Invoke-WebRequest -UseBasicParsing -Uri "$release/$file" -OutFile $zip
    $checksumFile=Join-Path $temporaryEngine "SHA512-SUMS.txt"
    Invoke-WebRequest -UseBasicParsing -Uri "$release/SHA512-SUMS.txt" -OutFile $checksumFile
    $checks=[IO.File]::ReadAllText($checksumFile)
    $match=[regex]::Match([string]$checks, '(?im)^([0-9a-f]{128})\s+\*?'+[regex]::Escape($file)+'\s*$')
    if(-not $match.Success -or (Get-FileHash $zip -Algorithm SHA512).Hash -ne $match.Groups[1].Value){throw 'Official engine archive failed its published SHA-512 check.'}
    Expand-Archive -LiteralPath $zip -DestinationPath "$temporaryEngine/extracted"
    $Engine=Join-Path $temporaryEngine 'extracted/Godot_v4.6.3-stable_win64.exe'
  } else {
    $pick=New-Object System.Windows.Forms.OpenFileDialog
    $pick.Title='Choose the extracted Godot 4.6.3 Windows x86_64 executable'
    $pick.Filter='Godot executable (*.exe)|*.exe'
    if($pick.ShowDialog() -ne 'OK'){return}
    $Engine=$pick.FileName
  }
}
if(-not (Test-Path -LiteralPath $Engine -PathType Leaf)){throw 'The selected engine file is missing.'}
$version=((& $Engine --headless --version | Out-String).Trim())
if($version -notlike '4.6.3.*'){throw "Expected Godot 4.6.3 x64. Received $version"}
$dest=[IO.Path]::GetFullPath($Destination)
if($dest.TrimEnd('\') -eq ([IO.Path]::GetFullPath($root)).TrimEnd('\')){throw 'Choose a destination separate from the extracted release.'}
New-Item -ItemType Directory -Force -Path "$dest\bin" | Out-Null
Copy-Item -LiteralPath $Engine -Destination "$dest\bin\godot.exe" -Force
$files=@('Player.cmd','README.md','LICENSE')
$packs=@('player.pck')
if(-not $PlayerOnly){$files+='Studio.cmd';$packs+='studio.pck'}
foreach($f in $files){Copy-Item -LiteralPath "$root\$f" -Destination "$dest\$f" -Force}
$packDir=if(Test-Path -LiteralPath "$root\bin\windows\studio.pck"){ "$root\bin\windows" }else{ "$root\bin" }
if(-not $PlayerOnly -and (Test-Path -LiteralPath "$packDir\python\python.exe")){
  New-Item -ItemType Directory -Force -Path "$dest\bin\python" | Out-Null
  Copy-Item -Path "$packDir\python\*" -Destination "$dest\bin\python" -Recurse -Force
}
foreach($f in $packs){Copy-Item -LiteralPath "$packDir\$f" -Destination "$dest\bin\$f" -Force}
foreach($dir in @('examples','docs','licenses','gateway','tools','firmware','packaging')){
  New-Item -ItemType Directory -Force -Path "$dest\$dir" | Out-Null
  Copy-Item -Path "$root\$dir\*" -Destination "$dest\$dir" -Recurse -Force
}
New-Item -ItemType Directory -Force -Path "$dest\tests" | Out-Null
Copy-Item -LiteralPath "$root\tests\results" -Destination "$dest\tests" -Recurse -Force
$menu=Join-Path ([Environment]::GetFolderPath('Programs')) $label
New-Item -ItemType Directory -Path $menu -Force | Out-Null
$shell=New-Object -ComObject WScript.Shell
foreach($f in $packs){
  $role=[IO.Path]::GetFileNameWithoutExtension($f)
  $name=(Get-Culture).TextInfo.ToTitleCase($role)
  $lnk=$shell.CreateShortcut("$menu\OpenExhibit $name.lnk")
  $lnk.TargetPath="$dest\bin\godot.exe"
  $lnk.Arguments="--main-pack `"$dest\bin\$f`" -- --examples `"$dest\examples`""
  $lnk.WorkingDirectory=$dest
  $lnk.Save()
}
Write-Host "Installed $label in $dest"

} finally {
  if($temporaryEngine -and (Test-Path -LiteralPath $temporaryEngine)){Remove-Item -LiteralPath $temporaryEngine -Recurse -Force}
}
