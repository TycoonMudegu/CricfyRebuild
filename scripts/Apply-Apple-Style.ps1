param([string]$Project = (Join-Path (Split-Path -Parent $PSScriptRoot) 'decoded'))
$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
& (Join-Path $workspace '.tools\python\python.exe') (Join-Path $PSScriptRoot 'apple_style.py') $Project
if ($LASTEXITCODE -ne 0) { throw 'Apple TV style resource update failed.' }
& (Join-Path $PSScriptRoot 'Apply-App-Edits.ps1') -Project $Project
