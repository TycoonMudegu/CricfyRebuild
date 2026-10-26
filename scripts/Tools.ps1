$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
$toolRoot = Join-Path $workspace '.tools'
$java = @(Get-ChildItem -Path (Join-Path $toolRoot 'java\*\bin\java.exe') -File -ErrorAction SilentlyContinue)
$apktool = Join-Path $toolRoot 'downloads\apktool_3.0.3.jar'
if ($java.Count -ne 1 -or -not (Test-Path -LiteralPath $apktool)) {
    throw 'Run scripts\Setup-Tools.ps1 first.'
}
$java = $java[0].FullName
$framework = Join-Path $toolRoot 'framework'
$javaTemp = Join-Path $toolRoot 'tmp'
New-Item -ItemType Directory -Path $framework,$javaTemp -Force | Out-Null
$javaOptions = @('-Xmx2G', "-Djava.io.tmpdir=$javaTemp")
