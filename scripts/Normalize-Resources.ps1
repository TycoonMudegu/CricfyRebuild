param(
    [string]$Apk = (Join-Path (Split-Path -Parent $PSScriptRoot) 'CRICFy_v7.3.apk'),
    [string]$Output = (Join-Path (Split-Path -Parent $PSScriptRoot) 'analysis\CRICFy-resource-map.apk')
)
$ErrorActionPreference = 'Stop'
if ([IO.Path]::GetFullPath($Apk) -eq [IO.Path]::GetFullPath($Output)) {
    throw 'The normalized copy must use a different path from the original APK.'
}
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead($Apk)
try {
    $entry = $archive.GetEntry('resources.arsc')
    $stream = $entry.Open()
    $memory = New-Object IO.MemoryStream
    try { $stream.CopyTo($memory); $data = $memory.ToArray() }
    finally { $stream.Dispose(); $memory.Dispose() }
} finally { $archive.Dispose() }

if ([BitConverter]::ToUInt32($data,8) -ne 1) { throw 'Expected one resource package.' }
$package = [int][BitConverter]::ToUInt16($data,2)
while ([BitConverter]::ToUInt16($data,$package) -ne 0x0200) {
    $package += [int][BitConverter]::ToUInt32($data,$package + 4)
    if ($package -ge $data.Length) { throw 'Resource package not found.' }
}
$pool = $package + [int][BitConverter]::ToUInt32($data,$package + 268)
$oldPoolSize = [int][BitConverter]::ToUInt32($data,$pool + 4)
$count = [int][BitConverter]::ToUInt32($data,$pool + 8)
if ([BitConverter]::ToUInt32($data,$pool + 12) -ne 0) { throw 'Unexpected styled type-name pool.' }
$flags = [BitConverter]::ToUInt32($data,$pool + 16)
$stringStart = [int][BitConverter]::ToUInt32($data,$pool + 20)
$headerSize = [int][BitConverter]::ToUInt16($data,$pool + 2)
$names = for ($index = 0; $index -lt $count; $index++) {
    $position = $pool + $stringStart + [int][BitConverter]::ToUInt32($data,$pool + $headerSize + $index * 4)
    if (($flags -band 0x100) -ne 0) {
        if ($data[$position] -ge 128 -or $data[$position + 1] -ge 128) { throw 'Unexpected long resource type name.' }
        [Text.Encoding]::UTF8.GetString($data,$position + 2,[int]$data[$position + 1])
    } else {
        $length = [int][BitConverter]::ToUInt16($data,$position)
        [Text.Encoding]::Unicode.GetString($data,$position + 2,$length * 2)
    }
}

# v7.3 mislabels these type IDs. Numeric resource IDs and resource values stay intact.
$fixes = @(
    @{ Index = 3; Before = 'style'; After = 'attr' },
    @{ Index = 9; Before = 'attr'; After = 'id' },
    @{ Index = 15; Before = 'id'; After = 'mipmap' },
    @{ Index = 20; Before = 'plurals'; After = 'style' }
)
foreach ($fix in $fixes) {
    if ($names[$fix.Index] -ne $fix.Before) { throw "Unexpected type map at ID $($fix.Index + 1). This normalization is specific to CRICFy v7.3." }
    $names[$fix.Index] = $fix.After
}

$textData = New-Object IO.MemoryStream
$offsets = @()
foreach ($name in $names) {
    $offsets += [uint32]$textData.Position
    $encoded = [Text.Encoding]::UTF8.GetBytes($name)
    $textData.WriteByte([byte]$name.Length)
    $textData.WriteByte([byte]$encoded.Length)
    $textData.Write($encoded,0,$encoded.Length)
    $textData.WriteByte(0)
}
$newStringStart = 28 + $count * 4
$newPoolSize = [int]([Math]::Ceiling(($newStringStart + $textData.Length) / 4.0) * 4)
$poolMemory = New-Object IO.MemoryStream
$writer = New-Object IO.BinaryWriter($poolMemory)
try {
    $writer.Write([uint16]1); $writer.Write([uint16]28); $writer.Write([uint32]$newPoolSize)
    $writer.Write([uint32]$count); $writer.Write([uint32]0); $writer.Write([uint32]0x100)
    $writer.Write([uint32]$newStringStart); $writer.Write([uint32]0)
    foreach ($offset in $offsets) { $writer.Write([uint32]$offset) }
    $writer.Write($textData.ToArray())
    while ($poolMemory.Length -lt $newPoolSize) { $writer.Write([byte]0) }
    $newPool = $poolMemory.ToArray()
} finally { $writer.Dispose(); $poolMemory.Dispose(); $textData.Dispose() }

$delta = $newPoolSize - $oldPoolSize
$normalized = New-Object byte[] ($data.Length + $delta)
[Array]::Copy($data,0,$normalized,0,$pool)
[Array]::Copy($newPool,0,$normalized,$pool,$newPool.Length)
[Array]::Copy($data,$pool + $oldPoolSize,$normalized,$pool + $newPoolSize,$data.Length - $pool - $oldPoolSize)
[BitConverter]::GetBytes([uint32]$normalized.Length).CopyTo($normalized,4)
[BitConverter]::GetBytes([uint32]([BitConverter]::ToUInt32($data,$package + 4) + $delta)).CopyTo($normalized,$package + 4)
$keyOffset = [int][BitConverter]::ToUInt32($data,$package + 276)
if ($package + $keyOffset -gt $pool) {
    [BitConverter]::GetBytes([uint32]($keyOffset + $delta)).CopyTo($normalized,$package + 276)
}

New-Item -ItemType Directory -Path (Split-Path -Parent $Output) -Force | Out-Null
Copy-Item -LiteralPath $Apk -Destination $Output -Force
$archive = [IO.Compression.ZipFile]::Open($Output,[IO.Compression.ZipArchiveMode]::Update)
try {
    $archive.GetEntry('resources.arsc').Delete()
    $entry = $archive.CreateEntry('resources.arsc',[IO.Compression.CompressionLevel]::NoCompression)
    $stream = $entry.Open()
    try { $stream.Write($normalized,0,$normalized.Length) } finally { $stream.Dispose() }
} finally { $archive.Dispose() }
Write-Host "Normalized resource type names in a copy: $Output"
