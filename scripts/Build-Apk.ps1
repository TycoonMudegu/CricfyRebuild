param(
    [string]$Project = (Join-Path (Split-Path -Parent $PSScriptRoot) 'decoded'),
    [string]$Output = (Join-Path (Split-Path -Parent $PSScriptRoot) 'build\CRICFy-Preview-unsigned.apk'),
    [switch]$Sign,
    [switch]$UsePreviewSignerPin,
    [string]$SignedOutput = (Join-Path (Split-Path -Parent $PSScriptRoot) 'build\CRICFy-Preview.apk')
)
. (Join-Path $PSScriptRoot 'Tools.ps1')
if (-not (Test-Path -LiteralPath (Join-Path $Project 'apktool.yml'))) {
    throw "Apktool project not found: $Project"
}
$outputPath = [System.IO.Path]::GetFullPath($Output)
if ($outputPath -eq (Join-Path $workspace 'CRICFy_v7.3.apk')) {
    throw 'Choose an output path other than the original APK.'
}
New-Item -ItemType Directory -Path (Split-Path -Parent $outputPath) -Force | Out-Null
if ($UsePreviewSignerPin) {
    & (Join-Path $PSScriptRoot 'Apply-Native-Signer.ps1') -Project $Project
} else {
    & (Join-Path $PSScriptRoot 'Restore-Vendor-Native.ps1') -Project $Project
}
try {
    & $java @javaOptions -jar $apktool b $Project -p $framework -o $outputPath
    if ($LASTEXITCODE -ne 0) { throw "Apktool build failed with exit code $LASTEXITCODE" }
    Write-Host "Built unsigned APK: $outputPath"
    if ($Sign) {
        & (Join-Path $PSScriptRoot 'Sign-Apk.ps1') -Apk $outputPath -Output $SignedOutput
    } else {
        Write-Host 'Sign the rebuilt APK before installing it on Android.'
    }
} finally {
    if ($UsePreviewSignerPin) {
        & (Join-Path $PSScriptRoot 'Restore-Vendor-Native.ps1') -Project $Project
    }
}
