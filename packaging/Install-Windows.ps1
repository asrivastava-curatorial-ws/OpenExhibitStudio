# Compatibility wrapper (0.2 name). Setup now runs in place; -Shortcuts adds Start-menu entries.
[CmdletBinding()]
param([string]$Engine, [switch]$PlayerOnly, [switch]$DownloadEngine, [string]$Destination)
$args2 = @('-Shortcuts')
if ($Engine) { $args2 += @('-Engine', $Engine) }
& (Join-Path $PSScriptRoot 'Setup-Windows.ps1') @args2
