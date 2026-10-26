"""Apply the neutral TV design to all custom resources; preserve library widgets."""
import colorsys
import json
import re
import shutil
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROJECT = Path(sys.argv[1])
RES = PROJECT / 'res'
ANDROID = 'http://schemas.android.com/apk/res/android'
APP = 'http://schemas.android.com/apk/res-auto'
ET.register_namespace('android', ANDROID)
ET.register_namespace('app', APP)
A = lambda name: '{' + ANDROID + '}' + name


def save(tree, path):
    ET.indent(tree, space='    ')
    tree.write(path, encoding='utf-8', xml_declaration=True)


def warm_color(value):
    if not re.fullmatch(r'#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?', value):
        return False
    rgb = value[-6:]
    r, g, b = (int(rgb[i:i + 2], 16) / 255 for i in (0, 2, 4))
    hue, saturation, brightness = colorsys.rgb_to_hsv(r, g, b)
    return (0.018 <= hue <= 0.17 and saturation > 0.3 and brightness > 0.05) or rgb.lower() in {'e01f12', 'ff5a1f', 'ff6a2c', 'ff9d2f'}


for source in (ROOT / 'ui-res/font').glob('*'):
    destination = RES / 'font' / source.name
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, destination)
for relative in ('drawable/bg_splash_premium.xml', 'layout/activity_splash.xml', 'layout/error_layout.xml', 'values/ui_styles.xml'):
    shutil.copyfile(ROOT / 'ui-res' / relative, RES / relative)
shutil.copyfile(ROOT / 'ui-res/font/ui_inter.xml', RES / 'font/alata.xml')
license_dir = PROJECT / 'assets/fonts'
license_dir.mkdir(parents=True, exist_ok=True)
shutil.copyfile(ROOT / 'design/fonts/OFL.txt', license_dir / 'OFL-Inter.txt')

recolored = []
gradients = []
fonts = []
library_prefixes = ('abc_', 'm3_', 'mtrl_', 'material_', 'design_', 'exo_', 'cast_', 'notification_', 'common_google_', 'googleg_')
for directory in RES.iterdir():
    if not directory.is_dir() or not directory.name.startswith(('layout', 'drawable', 'color')):
        continue
    for path in directory.glob('*.xml'):
        if path.name.startswith(library_prefixes) or path.name.startswith('$'):
            continue
        tree = ET.parse(path)
        root = tree.getroot()
        changed = False
        for parent in root.iter():
            for child in list(parent):
                if child.tag == 'gradient':
                    index = list(parent).index(child)
                    parent.remove(child)
                    ET.SubElement(parent, 'solid', {A('color'): '@color/ui_surface'})
                    gradients.append(str(path.relative_to(RES)))
                    changed = True
            for key, value in list(parent.attrib.items()):
                if value in ('@drawable/splashcricfy', '@drawable/sidebarcricfy'):
                    parent.set(key, '@drawable/ui_preview_logo')
                    changed = True
                if warm_color(value):
                    alpha = value[1:3] if len(value) == 9 else ''
                    parent.set(key, '#' + alpha + 'C0D5F4')
                    recolored.append(str(path.relative_to(RES)))
                    changed = True
            if parent.tag == 'corners':
                parent.set(A('radius'), '@dimen/ui_corner_radius')
                for attr in ('topLeftRadius', 'topRightRadius', 'bottomLeftRadius', 'bottomRightRadius'):
                    parent.attrib.pop(A(attr), None)
                changed = True
            if directory.name.startswith('layout'):
                if parent.tag.endswith(('TextView', 'Button', 'EditText', 'Chip')):
                    if parent.get(A('fontFamily')) != 'monospace':
                        previous = parent.get(A('fontFamily'), '')
                        weight = 'semibold' if 'bold' in parent.get(A('textStyle'), '') else 'medium' if 'medium' in previous else 'regular'
                        parent.set(A('fontFamily'), '@font/ui_inter_' + weight)
                        fonts.append(str(path.relative_to(RES)))
                        changed = True
                if parent.tag.endswith('MaterialCardView'):
                    parent.set('{' + APP + '}cardCornerRadius', '@dimen/ui_corner_radius')
                    parent.set('{' + APP + '}cardElevation', '0dp')
                    changed = True
        if changed:
            save(tree, path)

# Give both opponents the same logo-over-name order.
event_path = RES / 'layout/event_item.xml'
tree = ET.parse(event_path)
opponent = next(node for node in tree.getroot().iter() if node.get(A('id')) == '@id/teamBContainer')
flag = next(node for node in opponent if node.get(A('id')) == '@id/teamBFlag')
opponent.remove(flag)
opponent.insert(0, flag)
save(tree, event_path)

# The event-filter factory assigns these legacy selectors directly in code.
for old, replacement in (('chip_back.xml', 'ui_card_surface.xml'), ('chip_stroke.xml', 'ui_card_border.xml')):
    shutil.copyfile(RES / 'color' / replacement, RES / 'color' / old)

colors_path = RES / 'values/colors.xml'
tree = ET.parse(colors_path)
for color in tree.getroot():
    if color.tag == 'color' and color.text and warm_color(color.text) and not color.get('name', '').startswith(('m3_', 'mtrl_', 'material_', 'abc_')):
        color.text = '#C0D5F4'
        recolored.append('values/colors.xml:' + color.get('name'))
save(tree, colors_path)

for relative in ('values/styles.xml', 'values/ui_styles.xml'):
    path = RES / relative
    tree = ET.parse(path)
    for style in tree.getroot():
        if style.tag != 'style' or not (style.get('name') == 'Theme.Cricfy' or 'Cricfy.Ui' in style.get('name', '')):
            continue
        for item in style:
            if item.get('name') in ('fontFamily', 'android:fontFamily'):
                name = style.get('name', '')
                item.text = '@font/ui_inter_medium' if name == 'TextAppearance.Cricfy.Ui.Chip' else '@font/ui_inter_semibold' if name == 'TextAppearance.Cricfy.Ui.Toolbar' else '@font/ui_inter'
            if item.text and warm_color(item.text):
                item.text = '#C0D5F4'
    save(tree, path)

strings_path = RES / 'values/ui_strings.xml'
tree = ET.parse(strings_path)
if not any(node.get('name') == 'ui_splash_subtitle' for node in tree.getroot()):
    ET.SubElement(tree.getroot(), 'string', {'name': 'ui_splash_subtitle'}).text = 'Live sport. Beautifully simple.'
save(tree, strings_path)

# A single quiet monochrome spinner replaces the original colorful loading animation.
spinner = {
    'v': '5.7.4', 'fr': 60, 'ip': 0, 'op': 96, 'w': 96, 'h': 96, 'nm': 'Preview loading', 'ddd': 0, 'assets': [],
    'layers': [{'ddd': 0, 'ind': 1, 'ty': 4, 'nm': 'Loading ring', 'sr': 1, 'ks': {
        'o': {'a': 0, 'k': 100}, 'r': {'a': 1, 'k': [{'t': 0, 's': [0], 'e': [360], 'i': {'x': [0.667], 'y': [0.667]}, 'o': {'x': [0.333], 'y': [0.333]}}, {'t': 96, 's': [360]}]},
        'p': {'a': 0, 'k': [48, 48, 0]}, 'a': {'a': 0, 'k': [0, 0, 0]}, 's': {'a': 0, 'k': [100, 100, 100]}},
        'shapes': [{'ty': 'el', 'd': 1, 's': {'a': 0, 'k': [58, 58]}, 'p': {'a': 0, 'k': [0, 0]}, 'nm': 'Ring'},
                   {'ty': 'st', 'c': {'a': 0, 'k': [0.753, 0.835, 0.957, 1]}, 'o': {'a': 0, 'k': 100}, 'w': {'a': 0, 'k': 3}, 'lc': 2, 'lj': 2, 'nm': 'Stroke'},
                   {'ty': 'tm', 's': {'a': 0, 'k': 0}, 'e': {'a': 0, 'k': 72}, 'o': {'a': 0, 'k': 0}, 'm': 1, 'nm': 'Arc'}], 'ip': 0, 'op': 96, 'st': 0, 'bm': 0}]
}
raw_dir = RES / 'raw'
loading_files = list(raw_dir.glob('loading_anim.*'))
if len(loading_files) != 1:
    raise ValueError('Expected one loading animation resource')
loading_files[0].write_text(json.dumps(spinner, separators=(',', ':')), encoding='utf-8')

# Retain the live broadcast motion while bringing every fill/stroke into the same palette.
live_files = list(raw_dir.glob('live.*'))
for path in live_files:
    animation = json.loads(path.read_text(encoding='utf-8'))
    def recolor_animation(node):
        if isinstance(node, dict):
            if node.get('ty') in ('fl', 'st') and isinstance(node.get('c'), dict):
                node['c'] = {'a': 0, 'k': [0.753, 0.835, 0.957, 1]}
            for value in node.values():
                recolor_animation(value)
        elif isinstance(node, list):
            for value in node:
                recolor_animation(value)
    recolor_animation(animation)
    path.write_text(json.dumps(animation, separators=(',', ':')), encoding='utf-8')

# Keep the wide-screen home compact, with two match columns and the filters on one line.
land = RES / 'layout-land'
land.mkdir(exist_ok=True)
tree = ET.parse(RES / 'layout/fragment_home.xml')
root = tree.getroot()
container = next(node for node in root.iter() if node.get(A('id')) == '@id/event_content_container')
for child in list(container):
    if child.tag == 'TextView' and child.get(A('text')) in ('@string/ui_home_subtitle', '@string/ui_browse_sports'):
        container.remove(child)
title = next(node for node in container if node.tag == 'TextView' and node.get(A('text')) == '@string/ui_home_title')
title.set(A('textSize'), '28sp')
title.set(A('layout_marginTop'), '8dp')
title.set(A('layout_marginBottom'), '8dp')
heading = next(node for node in container if node.tag == 'TextView' and node.get(A('text')) == '@string/ui_live_upcoming')
filters = next(node for node in container if node.tag == 'HorizontalScrollView')
position = list(container).index(heading)
container.remove(heading)
container.remove(filters)
controls = ET.Element('LinearLayout', {A('orientation'): 'horizontal', A('gravity'): 'center_vertical', A('layout_width'): 'match_parent', A('layout_height'): '52dp', A('layout_marginTop'): '6dp', A('layout_marginBottom'): '8dp'})
heading.set(A('layout_width'), '0dp')
heading.set(A('layout_weight'), '1')
heading.set(A('textSize'), '21sp')
heading.set(A('layout_marginTop'), '0dp')
heading.set(A('layout_marginBottom'), '0dp')
filters.set(A('layout_width'), 'wrap_content')
filters.set(A('layout_marginBottom'), '0dp')
controls.extend((heading, filters))
container.insert(position, controls)
events = next(node for node in container if node.get(A('id')) == '@id/recycler')
events.set('{' + APP + '}layoutManager', 'androidx.recyclerview.widget.GridLayoutManager')
events.set('{' + APP + '}spanCount', '2')
save(tree, land / 'fragment_home.xml')

tree = ET.parse(RES / 'layout/event_cat_item.xml')
tree.getroot().set(A('layout_height'), '80dp')
image = next(node for node in tree.getroot().iter() if node.get(A('id')) == '@id/event_cat_image')
image.set(A('layout_width'), '32dp')
image.set(A('layout_height'), '32dp')
image.set(A('layout_marginTop'), '10dp')
save(tree, land / 'event_cat_item.xml')

tree = ET.parse(RES / 'layout/event_item.xml')
tree.getroot().set(A('layout_marginStart'), '6dp')
tree.getroot().set(A('layout_marginEnd'), '6dp')
content = tree.getroot()[0]
content.set(A('minHeight'), '148dp')
content.set(A('paddingBottom'), '10dp')
for node in tree.getroot().iter():
    view_id = node.get(A('id'))
    if view_id in ('@id/teamAFlag','@id/teamBFlag'):
        node.set(A('layout_width'), '40dp')
        node.set(A('layout_height'), '40dp')
    elif view_id in ('@id/teamAName','@id/teamBName'):
        node.set(A('textSize'), '13sp')
        node.set(A('layout_marginTop'), '6dp')
    elif view_id == '@id/constraintLayout2':
        node.set(A('layout_marginTop'), '10dp')
        node.set(A('layout_marginBottom'), '10dp')
        node.set(A('layout_marginVertical'), '10dp')
save(tree, land / 'event_item.xml')

report = {'gradientsReplaced': sorted(set(gradients)), 'warmColorsReplaced': sorted(set(recolored)), 'fontLayoutsUpdated': len(set(fonts)), 'font': 'Inter, bundled static weights 400/500/600/700', 'splash': 'Flat neutral background, Preview logo, quiet loading ring', 'landscape': 'Compact header, named sport filters, two-column event grid', 'nativeSignerLogicModified': False}
(ROOT / 'analysis/apple-style-report.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
print(json.dumps({key: value if not isinstance(value, list) else len(value) for key, value in report.items()}, indent=2))
