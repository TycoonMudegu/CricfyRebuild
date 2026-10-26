param(
    [string]$Adb = 'C:\LDPlayer\LDPlayer9\adb.exe',
    [string]$Serial,
    [string]$Package = 'com.cricfytv.sports',
    [string]$Output = (Join-Path (Split-Path -Parent $PSScriptRoot) 'analysis\runtime')
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $Adb -PathType Leaf)) { throw "ADB not found: $Adb" }
if ($Package -notmatch '^[A-Za-z0-9_.]+$') { throw 'Unexpected package name.' }

$devices = @(& $Adb devices -l)
if ($LASTEXITCODE -ne 0) { throw 'Could not query ADB devices.' }
if (-not $Serial) {
    $connected = @($devices | Where-Object { $_ -match '^\S+\s+device\b' })
    if ($connected.Count -eq 0) { throw 'No connected Android device. Enable local ADB debugging in LDPlayer.' }
    $Serial = ($connected[0] -split '\s+')[0]
}

New-Item -ItemType Directory -Path $Output -Force | Out-Null
$devices | Set-Content -LiteralPath (Join-Path $Output 'adb-devices.txt') -Encoding UTF8
$processIds = (& $Adb -s $Serial shell pidof $Package | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $processIds -notmatch '^\d+(\s+\d+)*$') {
    throw "The app is not running. Open $Package in LDPlayer, then collect its logs again."
}
$appProcessId = ($processIds -split '\s+')[0]
$logs = @(& $Adb -s $Serial logcat -d -v threadtime "--pid=$appProcessId")
if ($LASTEXITCODE -ne 0) { throw 'Could not collect app logcat output.' }
$logs | Set-Content -LiteralPath (Join-Path $Output 'cricfy-logcat.txt') -Encoding UTF8
& $Adb -s $Serial shell dumpsys package $Package | Set-Content -LiteralPath (Join-Path $Output 'cricfy-package.txt') -Encoding UTF8
$androidVersion = (& $Adb -s $Serial shell getprop ro.build.version.release | Out-String).Trim()
$apiLevel = (& $Adb -s $Serial shell getprop ro.build.version.sdk | Out-String).Trim()
$abiList = (& $Adb -s $Serial shell getprop ro.product.cpu.abilist | Out-String).Trim()
[ordered]@{
    serial = $Serial
    package = $Package
    processId = $appProcessId
    androidVersion = $androidVersion
    apiLevel = $apiLevel
    supportedAbis = $abiList
    collectedUtc = [DateTime]::UtcNow.ToString('o')
    logLines = $logs.Count
    dataCleared = $false
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $Output 'session.json') -Encoding UTF8
Write-Host "Collected $($logs.Count) app log lines into $Output"
Write-Host 'App data and emulator settings were preserved.'
