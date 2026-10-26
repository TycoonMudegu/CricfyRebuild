param([string]$Project = (Join-Path (Split-Path -Parent $PSScriptRoot) 'decoded'))
$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
$androidNs = 'http://schemas.android.com/apk/res/android'
$overlay = Join-Path $workspace 'ui-res'
foreach ($file in Get-ChildItem -LiteralPath $overlay -Recurse -File -Filter 'ui_preview_*') {
    $relative = $file.FullName.Substring($overlay.Length).TrimStart('\')
    $destination = Join-Path (Join-Path $Project 'res') $relative
    New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
    Copy-Item -LiteralPath $file.FullName -Destination $destination -Force
}
function Save-BrandXml($doc,[string]$path) {
    $settings = New-Object Xml.XmlWriterSettings
    $settings.Indent = $true
    $settings.IndentChars = '    '
    $settings.Encoding = New-Object Text.UTF8Encoding($false)
    $settings.NewLineChars = "`n"
    $writer = [Xml.XmlWriter]::Create($path,$settings)
    try { $doc.Save($writer) } finally { $writer.Dispose() }
}
$stringsPath = Join-Path $Project 'res\values\strings.xml'
$strings = [xml](Get-Content -LiteralPath $stringsPath -Raw)
$name = $strings.resources.string | Where-Object { $_.name -eq 'app_name' }
if (-not $name) { throw 'App name resource not found.' }
$name.InnerText = 'CRICFy Preview'
Save-BrandXml $strings $stringsPath
$manifestPath = Join-Path $Project 'AndroidManifest.xml'
$manifest = [xml](Get-Content -LiteralPath $manifestPath -Raw)
$attributes = @{ icon = '@mipmap/ui_preview_launcher'; roundIcon = '@mipmap/ui_preview_launcher'; logo = '@drawable/ui_preview_logo'; banner = '@drawable/ui_preview_banner' }
foreach ($key in $attributes.Keys) {
    $attribute = $manifest.CreateAttribute('android',$key,$androidNs)
    $attribute.Value = $attributes[$key]
    [void]$manifest.manifest.application.Attributes.SetNamedItem($attribute)
}
Save-BrandXml $manifest $manifestPath
$splashPath = Join-Path $Project 'res\layout\activity_splash.xml'
$splash = [xml](Get-Content -LiteralPath $splashPath -Raw)
$namespaces = New-Object Xml.XmlNamespaceManager($splash.NameTable)
$namespaces.AddNamespace('android',$androidNs)
$image = $splash.SelectSingleNode("//*[@android:id='@id/splash_img']",$namespaces)
if (-not $image) { throw 'Splash logo view not found.' }
[void]$image.SetAttribute('srcCompat','http://schemas.android.com/apk/res-auto','@drawable/ui_preview_logo')
Save-BrandXml $splash $splashPath
Write-Host 'Applied CRICFy Preview name, launcher icon, TV banner, and splash logo.'
