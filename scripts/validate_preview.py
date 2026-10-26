"""Check rebuilt resource identity, view bindings, DEX integrity, and native scope."""
import argparse
import hashlib
import json
import struct
import xml.etree.ElementTree as ET
import zipfile
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
A = '{http://schemas.android.com/apk/res/android}'
LIBRARY = ('abc_', 'm3_', 'mtrl_', 'material_', 'design_', 'exo_', 'cast_', 'notification_', 'common_google_', 'googleg_', '$')


def public_ids(res):
    return {(x.get('type'), x.get('name')): x.get('id') for x in ET.parse(res / 'values/public.xml').getroot() if x.tag == 'public'}


def bindings(path):
    return {x.get(A + 'id'): x.tag for x in ET.parse(path).getroot().iter() if x.get(A + 'id')}


def main(apk, project, output, expect_pin):
    apk, project = Path(apk), Path(project)
    baseline = ROOT / 'analysis/ui-baseline/res'
    res = project / 'res'
    issues = []
    old_ids, new_ids = public_ids(baseline), public_ids(res)
    for name, value in old_ids.items():
        if new_ids.get(name) != value:
            issues.append(f'Resource ID changed: {name}')
    layouts = view_ids = 0
    for original in baseline.glob('layout*/*.xml'):
        target = res / original.relative_to(baseline)
        if not target.exists():
            issues.append(f'Missing layout: {target}')
            continue
        layouts += 1
        old, new = bindings(original), bindings(target)
        view_ids += len(old)
        for key, cls in old.items():
            if new.get(key) != cls:
                issues.append(f'View binding changed: {target.name} {key} {cls} -> {new.get(key)}')
    # New qualified variants must expose the same original binding contract.
    for target in res.glob('layout-*/*.xml'):
        if (baseline / target.relative_to(res)).exists():
            continue
        original = baseline / 'layout' / target.name
        if original.exists():
            for key, cls in bindings(original).items():
                if bindings(target).get(key) != cls:
                    issues.append(f'Qualified binding changed: {target.relative_to(res)} {key}')
    manifest = ET.parse(project / 'AndroidManifest.xml').getroot()
    if manifest.get('package') != 'com.cricfytv.studio':
        issues.append('Unexpected Preview package')
    for node in manifest.iter():
        for key, value in node.attrib.items():
            if (key.endswith('authorities') or node.tag in ('permission', 'uses-permission')) and value.startswith('com.cricfytv.sports'):
                issues.append('Preview retains an original provider or permission namespace')
    gradients = []
    text_nodes = 0
    for path in res.glob('*/*.xml'):
        if path.name.startswith(LIBRARY) or not path.parent.name.startswith(('layout', 'drawable', 'color')):
            continue
        for node in ET.parse(path).getroot().iter():
            if node.tag == 'gradient':
                gradients.append(str(path.relative_to(res)))
            if path.parent.name.startswith('layout') and node.tag.endswith(('TextView', 'Button', 'EditText', 'Chip')):
                text_nodes += 1
                font = node.get(A + 'fontFamily', '')
                if font != 'monospace' and not font.startswith('@font/ui_inter'):
                    issues.append(f'Font missing: {path.name} {node.get(A + "id")}')
    if gradients:
        issues.append('Custom gradients remain: ' + ', '.join(gradients))
    dex_checks, native_changes = [], []
    with zipfile.ZipFile(ROOT / 'CRICFy_v7.3.apk') as original, zipfile.ZipFile(apk) as built:
        for name in ('classes.dex', 'classes2.dex'):
            data = built.read(name)
            checks = {
                'name': name,
                'sha1Valid': data[12:32] == hashlib.sha1(data[32:]).digest(),
                'adler32Valid': struct.unpack_from('<I', data, 8)[0] == (zlib.adler32(data[12:]) & 0xffffffff),
                'matchesEditedProject': data == (project / name).read_bytes(),
                'sameLengthAsOriginal': len(data) == len(original.read(name)),
            }
            dex_checks.append(checks)
            if not all(checks[k] for k in checks if k != 'name'):
                issues.append(f'DEX integrity failed: {name}')
        native = [n for n in original.namelist() if n.startswith('lib/') and n.endswith('.so')]
        old_pin = bytes.fromhex('f2cd86fcbc92461a3300cec47b6f74d20f0c89dd7162ecc333b3dd2c16e79841')
        new_pin = hashlib.sha256((ROOT / '.tools/keys/cricfy-ui-test.cer').read_bytes()).digest()
        for name in native:
            old, new = original.read(name), built.read(name)
            if old != new:
                expected = old
                if name.endswith('/libnative-lib.so'):
                    for start in (0, 16):
                        assert expected.count(old_pin[start:start + 16]) == 1
                        expected = expected.replace(old_pin[start:start + 16], new_pin[start:start + 16])
                native_changes.append({'file': name, 'onlyCertificateFingerprintChanged': new == expected, 'changedBytes': sum(a != b for a, b in zip(old, new)), 'sameLength': len(old) == len(new)})
        if expect_pin:
            if len(native_changes) != 4 or not all(x['onlyCertificateFingerprintChanged'] and x['changedBytes'] == 32 and x['sameLength'] for x in native_changes):
                issues.append('Proposed native change exceeds the four certificate fingerprints')
        elif native_changes:
            issues.append('UI-review build contains changed native libraries')
        original_assets = [n for n in original.namelist() if n.startswith('assets/') and not n.endswith('/')]
        if not all(original.read(n) == built.read(n) for n in original_assets):
            issues.append('An original asset changed')
    report = {
        'apk': str(apk.relative_to(ROOT) if apk.is_absolute() else apk),
        'sha256': hashlib.sha256(apk.read_bytes()).hexdigest(),
        'appName': 'CRICFy Preview', 'package': manifest.get('package'),
        'originalResourceIdsPreserved': len(old_ids),
        'existingLayoutsChecked': layouts, 'existingViewBindingsPreserved': view_ids,
        'customTextNodesWithBundledFonts': text_nodes, 'customGradients': gradients,
        'dexChecks': dex_checks,
        'nativeLibraryCount': len(native), 'nativeChanges': native_changes,
        'originalAssetsPreserved': len(original_assets),
        'proposedSignerPinIncluded': expect_pin,
        'runtimeHomeVerified': False,
        'startupStatus': 'Native signer proposal awaits explicit approval; UI-review build retains vendor pin and reaches expected configuration rejection',
        'issues': issues,
    }
    Path(output).write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps(report, indent=2))
    if issues:
        raise SystemExit(1)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('apk')
    parser.add_argument('--project', default=str(ROOT / 'decoded'))
    parser.add_argument('--output', default=str(ROOT / 'analysis/preview-validation.json'))
    parser.add_argument('--expect-preview-pin', action='store_true')
    args = parser.parse_args()
    main(args.apk, args.project, args.output, args.expect_preview_pin)
