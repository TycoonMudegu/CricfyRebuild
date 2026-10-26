param(
    [Parameter(Mandatory = $true)][string]$Uri,
    [Parameter(Mandatory = $true)][string]$Destination,
    [Parameter(Mandatory = $true)][long]$Size,
    [Parameter(Mandatory = $true)][string]$Sha256
)
$ErrorActionPreference = 'Stop'

# Bounded requests avoid stalled full-file responses and allow interrupted downloads to resume.
$file = [System.IO.File]::Open($Destination,'OpenOrCreate','ReadWrite','None')
try {
    if ($file.Length -ge $Size) { $file.SetLength(0) }
    $position = $file.Length
    [void]$file.Seek($position,'Begin')
    $nextReport = $position
    while ($position -lt $Size) {
        $end = [Math]::Min($position + 1048576 - 1,$Size - 1)
        for ($attempt = 0; $attempt -lt 3; $attempt++) {
            $response = $null
            try {
                $request = [System.Net.HttpWebRequest]::Create($Uri)
                $request.Timeout = 20000
                $request.ReadWriteTimeout = 20000
                $request.AddRange($position,$end)
                $response = $request.GetResponse()
                $expectedRange = "bytes $position-$end/$Size"
                if ([int]$response.StatusCode -ne 206 -or $response.Headers['Content-Range'] -ne $expectedRange) {
                    throw "Unexpected range response: $($response.Headers['Content-Range'])"
                }
                $stream = $response.GetResponseStream()
                $buffered = New-Object System.IO.MemoryStream
                try {
                    $stream.CopyTo($buffered)
                    if ($buffered.Length -ne ($end - $position + 1)) { throw 'Incomplete download chunk' }
                    $chunk = $buffered.ToArray()
                    $file.Write($chunk,0,$chunk.Length)
                } finally {
                    $buffered.Dispose()
                }
                $position = $end + 1
                break
            } catch {
                $file.SetLength($position)
                [void]$file.Seek($position,'Begin')
                if ($attempt -eq 2) { throw }
            } finally {
                if ($response) { $response.Dispose() }
            }
        }
        if ($position -ge $nextReport) {
            Write-Host ('Downloaded {0:N1} / {1:N1} MiB' -f ($position / 1MB),($Size / 1MB))
            $nextReport = $position + 8MB
        }
    }
} finally {
    $file.Dispose()
}
if ((Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash -ne $Sha256) {
    throw "Checksum mismatch: $Destination. Run setup again to download a fresh copy."
}
