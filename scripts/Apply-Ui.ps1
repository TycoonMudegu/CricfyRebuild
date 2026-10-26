param([string]$Project = (Join-Path (Split-Path -Parent $PSScriptRoot) 'decoded'))
$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
$androidNs = 'http://schemas.android.com/apk/res/android'
$appNs = 'http://schemas.android.com/apk/res-auto'
if (-not (Test-Path -LiteralPath (Join-Path $Project 'apktool.yml'))) { throw 'Decode the APK first.' }

function Read-Resource([string]$relative) { return ,([xml](Get-Content -LiteralPath (Join-Path $Project $relative) -Raw)) }
function Save-Resource($doc,[string]$relative) {
    $settings = New-Object Xml.XmlWriterSettings
    $settings.Indent = $true
    $settings.IndentChars = '    '
    $settings.Encoding = New-Object Text.UTF8Encoding($false)
    $settings.NewLineChars = "`n"
    $writer = [Xml.XmlWriter]::Create((Join-Path $Project $relative),$settings)
    try { $doc.Save($writer) } finally { $writer.Dispose() }
}
function Set-Attributes($node,$values,[string]$prefix = 'android') {
    $uri = if ($prefix -eq 'app') { $appNs } else { $androidNs }
    foreach ($key in $values.Keys) {
        $attribute = $node.OwnerDocument.CreateAttribute($prefix,$key,$uri)
        $attribute.Value = [string]$values[$key]
        [void]$node.Attributes.SetNamedItem($attribute)
    }
}
function Find-View($doc,[string]$id) {
    $namespaces = New-Object Xml.XmlNamespaceManager($doc.NameTable)
    $namespaces.AddNamespace('android',$androidNs)
    $view = $doc.SelectSingleNode("//*[@android:id='@id/$id']",$namespaces)
    if (-not $view) { throw "Missing view: $id" }
    return $view
}
function Set-StyleItem($style,[string]$name,[string]$value) {
    $item = @($style.item | Where-Object { $_.name -eq $name }) | Select-Object -First 1
    if (-not $item) {
        $item = $style.OwnerDocument.CreateElement('item')
        $item.SetAttribute('name',$name)
        [void]$style.AppendChild($item)
    }
    $item.InnerText = $value
}

& (Join-Path $PSScriptRoot 'Write-Ui-Icons.ps1')
Copy-Item -Path (Join-Path $workspace 'ui-res\*') -Destination (Join-Path $Project 'res') -Recurse -Force
foreach ($name in @('stroke_color','cat_stroke')) {
    Copy-Item -LiteralPath (Join-Path $Project 'res\color\ui_card_border.xml') -Destination (Join-Path $Project "res\color\$name.xml") -Force
}

$colors = Read-Resource 'res\values\colors.xml'
$palette = @{
    bgPrimary = '#0D0F13'; bgSurface = '#191C22'; bgElevated = '#252A33'
    textPrimary = '#F5F5F7'; textSecondary = '#A4AAB7'; divider = '#343A45'
    greenAccent = '#C0D5F4'; cyanHighlight = '#C0D5F4'; colorPrimary = '#C0D5F4'; colorAccent = '#C0D5F4'; bluePrimary = '#303A4A'
    dlg_surface = '#191C22'; dlg_stroke = '#343A45'; dlg_primary = '#C0D5F4'; dlg_icon_tile_bg = '#252A33'
    dlg_action_bg = '#252A33'; dlg_action_bg_pressed = '#303A4A'; dlg_text_primary = '#F5F5F7'; dlg_text_secondary = '#A4AAB7'
}
foreach ($name in $palette.Keys) {
    $color = $colors.resources.color | Where-Object { $_.name -eq $name }
    if ($color) { $color.InnerText = $palette[$name] }
}
Save-Resource $colors 'res\values\colors.xml'

$styles = Read-Resource 'res\values\styles.xml'
$theme = $styles.resources.style | Where-Object { $_.name -eq 'Theme.Cricfy' }
if (-not $theme) { throw 'Theme.Cricfy not found.' }
$themeItems = @{
    'android:fontFamily' = 'sans-serif'; fontFamily = 'sans-serif'; colorPrimary = '@color/ui_accent'
    colorPrimaryVariant = '@color/ui_accent'; colorSecondary = '@color/ui_accent'; colorTertiary = '@color/ui_accent'
    colorOnPrimary = '@color/ui_background'; colorOnSecondary = '@color/ui_background'; colorOnTertiary = '@color/ui_background'
    colorPrimaryContainer = '@color/ui_surface_raised'; colorSecondaryContainer = '@color/ui_surface_raised'
    colorOnPrimaryContainer = '@color/ui_text'; colorOnSecondaryContainer = '@color/ui_text'
    colorSurfaceContainerHigh = '@color/ui_surface_raised'; colorSurfaceContainerHighest = '@color/ui_surface_raised'
    colorSurfaceContainerLowest = '@color/ui_background'; colorControlNormal = '@color/ui_text_secondary'; colorControlActivated = '@color/ui_accent'
    chipStyle = '@style/Widget.Cricfy.Ui.Chip'; 'android:windowLightStatusBar' = 'false'; 'android:windowLightNavigationBar' = 'false'
    'android:windowAnimationStyle' = '@style/Animation.Cricfy.Ui.Window'
}
foreach ($name in $themeItems.Keys) { Set-StyleItem $theme $name $themeItems[$name] }
Save-Resource $styles 'res\values\styles.xml'

$main = Read-Resource 'res\layout\activity_main.xml'
Set-Attributes (Find-View $main 'main_ly') @{ background = '@color/ui_background' }
Set-Attributes (Find-View $main 'toolbar') @{ layout_height = '64dp'; paddingStart = '8dp'; paddingEnd = '8dp' }
Set-Attributes (Find-View $main 'toolbar') @{ titleTextAppearance = '@style/TextAppearance.Cricfy.Ui.Toolbar'; titleTextColor = '@color/ui_text'; navigationIconTint = '@color/ui_text' } 'app'
Set-Attributes (Find-View $main 'blur_bottom') @{ background = '@android:color/transparent' }
Set-Attributes (Find-View $main 'bottom_bar_card') @{ layout_marginLeft = '@dimen/ui_page_padding'; layout_marginRight = '@dimen/ui_page_padding'; layout_marginHorizontal = '@dimen/ui_page_padding'; layout_marginBottom = '12dp' }
Set-Attributes (Find-View $main 'bottom_bar_card') @{ cardBackgroundColor = '@color/ui_surface'; cardCornerRadius = '@dimen/ui_corner_radius'; cardElevation = '0dp'; strokeColor = '@color/ui_border'; strokeWidth = '1dp' } 'app'
Set-Attributes (Find-View $main 'bottom_nav') @{ layout_height = '64dp'; soundEffectsEnabled = 'true' }
Set-Attributes (Find-View $main 'bottom_nav') @{ iconSize = '23dp'; iconTint = '@color/ui_text_secondary'; iconTintActive = '@color/ui_text'; indicatorColor = '@color/ui_surface_raised'; indicatorRadius = '@dimen/ui_corner_radius'; textColor = '@color/ui_text_selector' } 'app'
$divider = $main.SelectSingleNode('//com.google.android.material.divider.MaterialDivider')
Set-Attributes $divider @{ layout_height = '1dp' }
Set-Attributes $divider @{ dividerColor = '@color/ui_border' } 'app'
Save-Resource $main 'res\layout\activity_main.xml'

$top = Read-Resource 'res\layout\tv_top_ly.xml'
Set-Attributes $top.DocumentElement @{ paddingStart = '@dimen/ui_page_padding'; paddingEnd = '@dimen/ui_page_padding'; paddingTop = '12dp'; paddingBottom = '12dp'; background = '@color/ui_background' }
foreach ($id in @('events_btn','sports_btn','cats_btn','fav_btn')) {
    $view = Find-View $top $id
    $view.SetAttribute('style','@style/Widget.Cricfy.Ui.NavigationButton')
    Set-Attributes $view @{ layout_height = '48dp'; layout_marginStart = '8dp'; textColor = '@color/ui_text_selector' }
}
foreach ($id in @('menu_btn','search_btn')) {
    Set-Attributes (Find-View $top $id) @{ layout_width = '48dp'; layout_height = '48dp'; padding = '12dp'; background = '@drawable/ui_control_background'; soundEffectsEnabled = 'true'; stateListAnimator = '@animator/ui_card_motion' }
}
Set-Attributes (Find-View $top 'menu_btn') @{ contentDescription = '@string/ui_open_menu' }
Set-Attributes (Find-View $top 'search_btn') @{ contentDescription = '@string/search' }
Set-Attributes (Find-View $top 'title_txt') @{ textSize = '20sp'; fontFamily = 'sans-serif-medium'; textColor = '@color/ui_text' }
Save-Resource $top 'res\layout\tv_top_ly.xml'

$event = Read-Resource 'res\layout\event_item.xml'
Set-Attributes $event.DocumentElement @{ soundEffectsEnabled = 'true'; stateListAnimator = '@animator/ui_card_motion'; layout_marginBottom = '14dp' }
Set-Attributes $event.DocumentElement @{ cardCornerRadius = '@dimen/ui_corner_radius'; cardBackgroundColor = '@color/ui_card_surface'; strokeColor = '@color/ui_card_border'; cardElevation = '0dp'; rippleColor = '@color/ui_ripple' } 'app'
$content = $event.DocumentElement.FirstChild
Set-Attributes $content @{ background = '@drawable/ui_event_background'; paddingTop = '4dp'; paddingBottom = '16dp'; minHeight = '170dp' }
Set-Attributes (Find-View $event 'constraintLayout') @{ layout_marginTop = '12dp'; layout_width = '0dp'; layout_marginStart = '16dp'; layout_marginEnd = '16dp' }
Set-Attributes (Find-View $event 'title_txt') @{ textSize = '13sp'; fontFamily = 'sans-serif-medium'; textColor = '@color/ui_text_secondary'; textAllCaps = 'false'; ellipsize = 'end'; layout_width = '0dp' }
Set-Attributes (Find-View $event 'event_logo') @{ layout_width = '20dp'; layout_height = '20dp'; layout_marginEnd = '8dp' }
Set-Attributes (Find-View $event 'constraintLayout2') @{ paddingLeft = '16dp'; paddingRight = '16dp'; paddingHorizontal = '16dp'; layout_marginTop = '18dp'; layout_marginBottom = '14dp'; layout_marginVertical = '14dp' }
foreach ($id in @('teamAContainer','teamBContainer')) { Set-Attributes (Find-View $event $id) @{ orientation = 'vertical'; gravity = 'center' } }
foreach ($id in @('teamAFlag','teamBFlag')) {
    Set-Attributes (Find-View $event $id) @{ layout_width = '48dp'; layout_height = '48dp' }
    Set-Attributes (Find-View $event $id) @{ civ_border_color = '@color/ui_border'; civ_border_width = '1dp' } 'app'
}
foreach ($id in @('teamAName','teamBName')) {
    $view = Find-View $event $id
    foreach ($attribute in @('layout_weight','scrollHorizontally','marqueeRepeatLimit')) { $view.RemoveAttribute($attribute,$androidNs) }
    Set-Attributes $view @{ layout_width = 'match_parent'; textSize = '14sp'; fontFamily = 'sans-serif-medium'; textColor = '@color/ui_text'; gravity = 'center'; textAlignment = 'center'; singleLine = 'false'; maxLines = '2'; ellipsize = 'end'; layout_marginTop = '8dp'; layout_marginStart = '0dp'; layout_marginEnd = '0dp' }
}
Set-Attributes (Find-View $event 'center_ly') @{ minWidth = '76dp' }
Set-Attributes (Find-View $event 'time_text') @{ textSize = '15sp'; fontFamily = 'sans-serif-medium'; textColor = '@color/ui_accent' }
Set-Attributes (Find-View $event 'date_text') @{ textSize = '12sp'; fontFamily = 'sans-serif'; textColor = '@color/ui_text_secondary'; layout_marginTop = '4dp' }
foreach ($id in @('status_txt','hotLabel')) {
    Set-Attributes (Find-View $event $id) @{ background = '@drawable/ui_status_badge'; textColor = '@color/ui_accent'; fontFamily = 'sans-serif-medium'; textSize = '11sp'; paddingLeft = '10dp'; paddingRight = '10dp'; paddingHorizontal = '10dp'; paddingTop = '3dp'; paddingBottom = '3dp' }
}
Save-Resource $event 'res\layout\event_item.xml'

$message = Read-Resource 'res\layout\message_ly.xml'
Set-Attributes $message.DocumentElement @{ stateListAnimator = '@animator/ui_card_motion'; soundEffectsEnabled = 'true'; layout_marginBottom = '12dp' }
Set-Attributes $message.DocumentElement @{ cardCornerRadius = '@dimen/ui_corner_radius'; cardBackgroundColor = '@color/ui_surface'; strokeColor = '@color/ui_border'; cardElevation = '0dp' } 'app'
Set-Attributes $message.DocumentElement.FirstChild @{ layout_height = '48dp'; paddingLeft = '14dp'; paddingRight = '14dp'; paddingHorizontal = '14dp' }
Save-Resource $message 'res\layout\message_ly.xml'

foreach ($relative in @('res\layout\fragment_recycler.xml','res\layout\fragment_channels_new.xml')) {
    $doc = Read-Resource $relative
    Set-Attributes (Find-View $doc 'recycler') @{ padding = '@dimen/ui_page_padding'; paddingBottom = '@dimen/ui_home_bottom_inset'; scrollbars = 'none'; clipChildren = 'false' }
    Save-Resource $doc $relative
}

$menu = Read-Resource 'res\menu\toolbar_menu.xml'
Set-Attributes (Find-View $menu 'refresh_btn_top') @{ showAsAction = 'never' } 'app'
foreach ($id in @('not_item','favouriteFragment')) { Set-Attributes (Find-View $menu $id) @{ showAsAction = 'ifRoom' } 'app' }
Save-Resource $menu 'res\menu\toolbar_menu.xml'

foreach ($name in @('nav_default_enter_anim','nav_default_pop_enter_anim')) {
    Copy-Item -LiteralPath (Join-Path $Project 'res\anim\ui_page_enter.xml') -Destination (Join-Path $Project "res\anim\$name.xml") -Force
}
foreach ($name in @('nav_default_exit_anim','nav_default_pop_exit_anim')) {
    Copy-Item -LiteralPath (Join-Path $Project 'res\anim\ui_page_exit.xml') -Destination (Join-Path $Project "res\anim\$name.xml") -Force
}
& (Join-Path $PSScriptRoot 'Apply-Branding.ps1') -Project $Project
& (Join-Path $PSScriptRoot 'Apply-Apple-Style.ps1') -Project $Project
Write-Host 'Applied the home screen, sport selector, vector icons, and focus/press animations.'
