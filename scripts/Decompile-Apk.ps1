param(
    [string]$Apk = (Join-Path (Split-Path -Parent $PSScriptRoot) 'CRICFy_v7.3.apk'),
    [string]$Output = (Join-Path (Split-Path -Parent $PSScriptRoot) 'decoded')
)
. (Join-Path $PSScriptRoot 'Tools.ps1')
if (-not (Test-Path -LiteralPath $Apk -PathType Leaf)) { throw "APK not found: $Apk" }
if (Test-Path -LiteralPath $Output) {
    throw "Output already exists: $Output. Choose another -Output folder to preserve your edits."
}
# UI edits only need decoded resources. Preserve the original protected DEX files.
$normalizedApk = Join-Path $workspace 'analysis\CRICFy-resource-map.apk'
& (Join-Path $PSScriptRoot 'Normalize-Resources.ps1') -Apk $Apk -Output $normalizedApk
& $java @javaOptions -jar $apktool d $normalizedApk -s -p $framework -o $Output
if ($LASTEXITCODE -ne 0) { throw "Apktool decode failed with exit code $LASTEXITCODE" }
Write-Host "Editable resources with original DEX preserved: $Output"
