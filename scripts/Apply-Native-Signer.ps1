param([string]$Project = (Join-Path (Split-Path -Parent $PSScriptRoot) 'decoded'))
$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
& (Join-Path $PSScriptRoot 'Ensure-TestKey.ps1')
$certificate = Join-Path $workspace '.tools\keys\cricfy-ui-test.cer'
$expected = 'f2cd86fcbc92461a3300cec47b6f74d20f0c89dd7162ecc333b3dd2c16e79841'
$replacement = (Get-FileHash -LiteralPath $certificate -Algorithm SHA256).Hash.ToLowerInvariant()
function Bytes-FromHex([string]$hex) {
    $result = New-Object byte[] ($hex.Length / 2)
    for ($i = 0; $i -lt $result.Length; $i++) { $result[$i] = [Convert]::ToByte($hex.Substring($i * 2,2),16) }
    return ,$result
}
$oldBytes = Bytes-FromHex $expected
$newBytes = Bytes-FromHex $replacement
$encoding = [Text.Encoding]::GetEncoding(28591)
$updates = @()
foreach ($abi in @('arm64-v8a','armeabi-v7a','x86','x86_64')) {
    $path = Join-Path $Project "lib\$abi\libnative-lib.so"
    $data = [IO.File]::ReadAllBytes($path)
    $text = $encoding.GetString($data)
    $changes = @()
    for ($half = 0; $half -lt 2; $half++) {
        $offset = $half * 16
        $oldPattern = $encoding.GetString($oldBytes,$offset,16)
        $newPattern = $encoding.GetString($newBytes,$offset,16)
        $position = $text.IndexOf($oldPattern,[StringComparison]::Ordinal)
        if ($position -lt 0) {
            if ($text.IndexOf($newPattern,[StringComparison]::Ordinal) -lt 0) { throw "Unrecognized native certificate pin in $abi" }
            continue
        }
        if ($text.IndexOf($oldPattern,$position + 1,[StringComparison]::Ordinal) -ge 0) { throw "Ambiguous certificate fingerprint in $abi" }
        [Array]::Copy($newBytes,$offset,$data,$position,16)
        $changes += $position
    }
    $updates += [PSCustomObject]@{ path = $path; abi = $abi; data = $data; offsets = $changes }
}
# Validate every ABI before writing any. This changes certificate data, not executable instructions.
foreach ($update in $updates) {
    if ($update.offsets.Count -gt 0) { [IO.File]::WriteAllBytes($update.path,$update.data) }
    Write-Host "Native signer pin ready: $($update.abi)"
}
[ordered]@{ purpose = 'Pin the native startup verifier to this preview signing certificate'; originalCertificateSha256 = $expected; previewCertificateSha256 = $replacement; executableInstructionsModified = $false; otherNativeChecksModified = $false; libraries = @($updates | Select-Object abi,offsets) } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $workspace 'analysis\native-signer-patch.json') -Encoding UTF8
