. (Join-Path $PSScriptRoot 'Tools.ps1')
$keyDirectory = Join-Path $toolRoot 'keys'
$keystore = Join-Path $keyDirectory 'cricfy-ui-test.p12'
$certificate = Join-Path $keyDirectory 'cricfy-ui-test.cer'
$keytool = Join-Path (Split-Path -Parent $java) 'keytool.exe'
New-Item -ItemType Directory -Path $keyDirectory -Force | Out-Null
if (-not (Test-Path -LiteralPath $keystore)) {
    & $keytool -genkeypair -keystore $keystore -storetype PKCS12 -alias cricfy-ui -keyalg RSA -keysize 2048 -validity 3650 -dname 'CN=CRICFy UI Local Test' -storepass android -keypass android -noprompt
    if ($LASTEXITCODE -ne 0) { throw 'Could not create preview signing key.' }
}
if (-not (Test-Path -LiteralPath $certificate) -or (Get-Item -LiteralPath $certificate).LastWriteTimeUtc -lt (Get-Item -LiteralPath $keystore).LastWriteTimeUtc) {
    & $keytool -exportcert -keystore $keystore -storetype PKCS12 -alias cricfy-ui -storepass android -file $certificate
    if ($LASTEXITCODE -ne 0) { throw 'Could not export public signing certificate.' }
}
