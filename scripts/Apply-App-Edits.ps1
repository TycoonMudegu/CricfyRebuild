param([string]$Project = (Join-Path (Split-Path -Parent $PSScriptRoot) 'decoded'))
$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
& (Join-Path $workspace '.tools\python\python.exe') (Join-Path $PSScriptRoot 'apply_app_edits.py') $Project
if ($LASTEXITCODE -ne 0) { throw 'Application UI behavior patch failed.' }
$manifestPath = Join-Path $Project 'AndroidManifest.xml'
$manifest = [xml](Get-Content -LiteralPath $manifestPath -Raw)
$oldPackage = 'com.cricfytv.sports'
$newPackage = 'com.cricfytv.studio'
$manifest.manifest.SetAttribute('package',$newPackage)
foreach ($element in $manifest.SelectNodes('//*')) {
    foreach ($attribute in @($element.Attributes)) {
        if (($attribute.LocalName -eq 'authorities' -or ($element.LocalName -in @('permission','uses-permission') -and $attribute.LocalName -eq 'name') -or $attribute.LocalName -eq 'permission') -and $attribute.Value.StartsWith($oldPackage,[StringComparison]::Ordinal)) {
            $attribute.Value = $newPackage + $attribute.Value.Substring($oldPackage.Length)
        }
    }
}
$settings = New-Object Xml.XmlWriterSettings
$settings.Indent = $true
$settings.IndentChars = '    '
$settings.Encoding = New-Object Text.UTF8Encoding($false)
$settings.NewLineChars = "`n"
$writer = [Xml.XmlWriter]::Create($manifestPath,$settings)
try { $manifest.Save($writer) } finally { $writer.Dispose() }
Write-Host 'Preview has its own package identity and the Telegram popup trigger is disabled.'
