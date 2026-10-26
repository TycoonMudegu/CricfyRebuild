param(
    [string]$Apk = (Join-Path (Split-Path -Parent $PSScriptRoot) 'build\CRICFy-Preview-unsigned.apk'),
    [string]$Output = (Join-Path (Split-Path -Parent $PSScriptRoot) 'build\CRICFy-Preview.apk')
)
. (Join-Path $PSScriptRoot 'Tools.ps1')
$signer = Join-Path $toolRoot 'downloads\uber-apk-signer-1.3.0.jar'
if (-not (Test-Path -LiteralPath $Apk -PathType Leaf)) { throw "APK not found: $Apk" }
if (-not (Test-Path -LiteralPath $signer)) { throw 'Run Setup-Tools.ps1 to install the signer.' }
if ([IO.Path]::GetFullPath($Output) -eq (Join-Path $workspace 'CRICFy_v7.3.apk')) {
    throw 'Choose an output path other than the original APK.'
}
$keyDirectory = Join-Path $toolRoot 'keys'
$keystore = Join-Path $keyDirectory 'cricfy-ui-test.p12'
New-Item -ItemType Directory -Path $keyDirectory -Force | Out-Null
if (-not (Test-Path -LiteralPath $keystore)) {
    $keytool = Join-Path (Split-Path -Parent $java) 'keytool.exe'
    & $keytool -genkeypair -keystore $keystore -storetype PKCS12 -alias cricfy-ui -keyalg RSA -keysize 2048 -validity 3650 -dname 'CN=CRICFy UI Local Test' -storepass android -keypass android -noprompt
    if ($LASTEXITCODE -ne 0) { throw 'Failed to create the local test signing key.' }
}
$signingRoot = Join-Path $workspace 'build\signing'
$staging = Join-Path $signingRoot ([Guid]::NewGuid().ToString('N'))
& $java @javaOptions -jar $signer --apks $Apk --ks $keystore --ksAlias cricfy-ui --ksPass android --ksKeyPass android --out $staging
if ($LASTEXITCODE -ne 0) { throw "APK signing failed with exit code $LASTEXITCODE" }
$signedApks = @(Get-ChildItem -LiteralPath $staging -Filter '*.apk' -File)
if ($signedApks.Count -ne 1) { throw 'Expected exactly one signed APK.' }
New-Item -ItemType Directory -Path (Split-Path -Parent ([IO.Path]::GetFullPath($Output))) -Force | Out-Null
Copy-Item -LiteralPath $signedApks[0].FullName -Destination $Output -Force
Write-Host "Signed and verified local test APK: $Output"

# Delete only this invocation's generated staging directory, after preserving the signed APK.
$stagingPath = [IO.Path]::GetFullPath($staging)
$signingPath = [IO.Path]::GetFullPath($signingRoot).TrimEnd('\') + '\'
if (-not $stagingPath.StartsWith($signingPath,[StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe staging cleanup path.' }
Remove-Item -LiteralPath $stagingPath -Recurse -Force
