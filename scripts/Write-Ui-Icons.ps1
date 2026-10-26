$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
$vectors = Join-Path $workspace 'ui-res\drawable'
$svgs = Join-Path $workspace 'design\icons'
New-Item -ItemType Directory -Path $vectors,$svgs -Force | Out-Null

# Original, consistently drawn 24px outline icons. SVG sources and Android equivalents.
$icons = [ordered]@{
    ic_live_events = @('M6,4 H18 A3,3 0,0 1,21 7 V15 A3,3 0,0 1,18 18 H6 A3,3 0,0 1,3 15 V7 A3,3 0,0 1,6 4 Z','M10,8 L15,11 L10,14 Z','M9,21 H15 M12,18 V21')
    ic_sports = @('M8,3 H16 V8 A4,4 0,0 1,8 8 Z','M8,5 H5 V7 A4,4 0,0 0,9 11 M16,5 H19 V7 A4,4 0,0 1,15 11','M12,12 V17 M8,21 H16 M10,17 H14 V21 H10 Z')
    ic_cats = @('M5,3 H9 A2,2 0,0 1,11 5 V9 A2,2 0,0 1,9 11 H5 A2,2 0,0 1,3 9 V5 A2,2 0,0 1,5 3 Z','M15,3 H19 A2,2 0,0 1,21 5 V9 A2,2 0,0 1,19 11 H15 A2,2 0,0 1,13 9 V5 A2,2 0,0 1,15 3 Z','M5,13 H9 A2,2 0,0 1,11 15 V19 A2,2 0,0 1,9 21 H5 A2,2 0,0 1,3 19 V15 A2,2 0,0 1,5 13 Z','M15,13 H19 A2,2 0,0 1,21 15 V19 A2,2 0,0 1,19 21 H15 A2,2 0,0 1,13 19 V15 A2,2 0,0 1,15 13 Z')
    ic_search = @('M17.5,10.5 A7,7 0,1 1,3.5 10.5 A7,7 0,1 1,17.5 10.5','M16,16 L21,21')
    baseline_menu_24 = @('M4,6 H20 M4,12 H20 M4,18 H20')
    ic_clear = @('M6,6 L18,18 M18,6 L6,18')
    ic_fav = @('M20.4,4.6 A5.4,5.4 0,0 0,12 5.5 A5.4,5.4 0,0 0,3.6 11.9 L12,20 L20.4,11.9 A5.4,5.4 0,0 0,20.4 4.6 Z')
    ic_notification = @('M6,9 A6,6 0,0 1,18 9 V13 L20,17 H4 L6,13 Z','M10,21 H14 M12,1.5 V3')
    ic_refresh = @('M20,5 V11 H14','M19.2,15 A8,8 0,1 1,18.3 6.5 L20,9')
    ic_playlist = @('M4,5 H20 M4,11 H12 M4,17 H10','M16,12 L21,15.5 L16,19 Z')
    ic_edit = @('M14.5,5.5 L18.5,9.5','M4,20 L5,15 L16.5,3.5 A2.8,2.8 0,0 1,20.5 7.5 L9,19 Z')
    ui_chevron_right = @('M9,5 L16,12 L9,19')
}
foreach ($name in $icons.Keys) {
    $paths = $icons[$name]
    $androidPaths = ($paths | ForEach-Object {
        '    <path android:pathData="' + $_ + '" android:fillColor="@android:color/transparent" android:strokeColor="#F5F5F7" android:strokeWidth="1.7" android:strokeLineCap="round" android:strokeLineJoin="round" />'
    }) -join "`n"
    $svgPaths = ($paths | ForEach-Object { '    <path d="' + $_ + '" />' }) -join "`n"
    $vector = '<?xml version="1.0" encoding="utf-8"?>' + "`n" + '<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="24dp" android:height="24dp" android:viewportWidth="24" android:viewportHeight="24">' + "`n" + $androidPaths + "`n</vector>`n"
    $svg = '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">' + "`n" + $svgPaths + "`n</svg>`n"
    [IO.File]::WriteAllText((Join-Path $vectors "$name.xml"),$vector,(New-Object Text.UTF8Encoding($false)))
    [IO.File]::WriteAllText((Join-Path $svgs "$name.svg"),$svg,(New-Object Text.UTF8Encoding($false)))
}
Write-Host "Generated $($icons.Count) SVG icons and Android vector drawables."
