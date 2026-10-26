param([string]$Project = (Join-Path (Split-Path -Parent $PSScriptRoot) 'decoded'))
$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead((Join-Path $workspace 'CRICFy_v7.3.apk'))
try {
    foreach ($abi in @('arm64-v8a','armeabi-v7a','x86','x86_64')) {
        $entry = $archive.GetEntry("lib/$abi/libnative-lib.so")
        $stream = $entry.Open()
        $memory = New-Object IO.MemoryStream
        try { $stream.CopyTo($memory); $bytes = $memory.ToArray() } finally { $stream.Dispose(); $memory.Dispose() }
        [IO.File]::WriteAllBytes((Join-Path $Project "lib\$abi\libnative-lib.so"),$bytes)
    }
} finally { $archive.Dispose() }
Write-Host 'Original native libraries restored; the proposed preview pin was not applied.'
