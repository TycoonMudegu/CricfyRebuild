$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$workspace = Split-Path -Parent $PSScriptRoot
$toolRoot = Join-Path $workspace '.tools'
$downloads = Join-Path $toolRoot 'downloads'
New-Item -ItemType Directory -Path $downloads -Force | Out-Null

# Pinned official releases. Checksums are published by GitHub/Adoptium.
$packages = @(
    @{
        Name = 'python-3.12.10-embed-amd64.zip'
        Url = 'https://www.python.org/ftp/python/3.12.10/python-3.12.10-embed-amd64.zip'
        Sha256 = '4acbed6dd1c744b0376e3b1cf57ce906f9dc9e95e68824584c8099a63025a3c3'
        Size = 11133606
        Destination = 'python'
    },
    @{
        Name = 'apktool_3.0.3.jar'
        Url = 'https://github.com/iBotPeaches/Apktool/releases/download/v3.0.3/apktool_3.0.3.jar'
        Sha256 = 'dbf930b076c6b9be08d57c449cacefc3bdd6b71ebd59b3066fc0e1f5b14f9423'
        Size = 15478013
    },
    @{
        Name = 'jadx-1.5.6.zip'
        Url = 'https://github.com/skylot/jadx/releases/download/v1.5.6/jadx-1.5.6.zip'
        Sha256 = '545ea2be9c242511bc145755cf4bda2485ade42966e096f8b4d3da2a230e8974'
        Size = 72646741
        Destination = 'jadx'
    },
    @{
        Name = 'OpenJDK21U-jre_x64_windows_hotspot_21.0.12.1_1.zip'
        Url = 'https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.12.1%2B1/OpenJDK21U-jre_x64_windows_hotspot_21.0.12.1_1.zip'
        Sha256 = 'd35f31e712f0fcf6ac5a093edc90204fbff22f720ba3950bd09d331d5e621636'
        Size = 48999141
        Destination = 'java'
    },
    @{
        Name = 'uber-apk-signer-1.3.0.jar'
        Url = 'https://github.com/patrickfav/uber-apk-signer/releases/download/v1.3.0/uber-apk-signer-1.3.0.jar'
        Sha256 = 'e1299fd6fcf4da527dd53735b56127e8ea922a321128123b9c32d619bba1d835'
        Size = 3208194
    }
)

foreach ($package in $packages) {
    $archive = Join-Path $downloads $package.Name
    $needsDownload = -not (Test-Path -LiteralPath $archive)
    if (-not $needsDownload) {
        $needsDownload = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $package.Sha256
    }
    if ($needsDownload) {
        Write-Host "Downloading $($package.Name)..."
        & (Join-Path $PSScriptRoot 'Download-Verified.ps1') -Uri $package.Url -Destination $archive -Size $package.Size -Sha256 $package.Sha256
    }
    if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $package.Sha256) {
        throw "Checksum mismatch: $archive. Run Setup-Tools.ps1 again to retry."
    }
    if ($package.Destination) {
        $destination = Join-Path $toolRoot $package.Destination
        if (-not (Test-Path -LiteralPath $destination)) {
            Expand-Archive -LiteralPath $archive -DestinationPath $destination
        }
    }
    Write-Host "Verified $($package.Name)"
}
$pythonPaths = @('python312.zip','.','..\python-packages','..\..\scripts')
$pythonPaths | Set-Content -LiteralPath (Join-Path $toolRoot 'python\python312._pth') -Encoding ASCII
Write-Host 'Portable tools are ready in .tools.'
