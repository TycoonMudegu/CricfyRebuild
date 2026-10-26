"""Apply narrowly scoped UI behavior edits to original DEX, preserving code offsets."""
import argparse
import hashlib
import json
import struct
import zipfile
import zlib
from pathlib import Path
from inspect_apk import Dex
from readable_dex import WIDTH

ROOT = Path(__file__).resolve().parents[1]
OLD_PACKAGE = 'com.cricfytv.sports'
NEW_PACKAGE = 'com.cricfytv.studio'
AUTHORITY_SUFFIXES = ('.provider', '.fileprovider', '.androidx-startup', '.firebaseinitprovider', '.dynamic_receiver_not_exported_permission')


def instructions(dex, method):
    raw = dex.method_bytes(method)
    position = 0
    while position < method['units']:
        word = struct.unpack_from('<H', raw, position * 2)[0]
        if word == 0x0300:
            width, count = struct.unpack_from('<HI', raw, position * 2 + 2)
            if width not in (1, 2, 4, 8):
                return
            size = 4 + (width * count + 1) // 2
        elif word in (0x0100, 0x0200):
            count = struct.unpack_from('<H', raw, position * 2 + 2)[0]
            size = 4 + count * 2 if word == 0x0100 else 2 + count * 4
        else:
            size = WIDTH[word & 255]
        yield position, word, size
        position += size


def edit_dex(path):
    dex = Dex(path)
    data = bytearray(dex.data)
    popup_patches = []
    progress_colors = 0
    sport_labels = []
    tv_columns = 0
    fields = []
    for index in range(dex.u32(80)):
        position = dex.u32(84) + index * 8
        fields.append({'owner': dex.types[dex.u16(position)], 'type': dex.types[dex.u16(position + 2)], 'name': dex.strings[dex.u32(position + 4)]})
    category_name_field = next((index for index, field in enumerate(fields) if field == {'owner': 'Lkq0;', 'type': 'Ljava/lang/String;', 'name': 'b'}), None)
    for method in dex.defined:
        if method['class'] == 'Lmq0;' and method['name'] == 'k':
            raw = dex.method_bytes(method)
            listing = list(instructions(dex, method))
            for position, word, size in listing:
                if word & 255 != 0x52:
                    continue
                field_id = struct.unpack_from('<H', raw, position * 2 + 2)[0]
                if fields[field_id] != {'owner': 'Lkq0;', 'type': 'I', 'name': 'd'}:
                    continue
                register = (word >> 8) & 15
                following = position + size
                call = struct.unpack_from('<H', raw, following * 2)[0]
                assert call & 255 == 0x71
                called = dex.methods[struct.unpack_from('<H', raw, following * 2 + 2)[0]]
                assert called['class'] == 'Ljava/lang/String;' and called['name'] == 'valueOf' and called['proto'] == '(I)Ljava/lang/String;'
                result = struct.unpack_from('<H', raw, (following + 3) * 2)[0]
                assert result & 255 == 0x0C
                destination = result >> 8
                assert destination < 16
                base = method['code'] + 16
                struct.pack_into('<HH', data, base + position * 2, (word & 0xFF00) | 0x54, category_name_field)
                data[base + following * 2:base + (following + 3) * 2] = b'\0' * 6
                struct.pack_into('<H', data, base + (following + 3) * 2, 0 if destination == register else 0x07 | (destination << 8) | (register << 12))
                sport_labels.append({'method': method['index'], 'getterUnit': position})
        if method['class'] == 'Lcom/android/vending/fragments/HomeFragment;' and method['name'] == 'C':
            raw = dex.method_bytes(method)
            listing = list(instructions(dex, method))
            for item, (position, word, size) in enumerate(listing):
                if word & 255 != 0x70:
                    continue
                called = dex.methods[struct.unpack_from('<H', raw, position * 2 + 2)[0]]
                if called['class'] != 'Landroidx/recyclerview/widget/GridLayoutManager;' or called['name'] != '<init>' or called['proto'] != '(Landroid/content/Context;I)V':
                    continue
                registers = struct.unpack_from('<H', raw, position * 2 + 4)[0]
                column_register = (registers >> 8) & 15
                for earlier_position, earlier_word, _ in reversed(listing[max(0,item - 8):item]):
                    if earlier_word & 255 == 0x12 and (earlier_word >> 8) & 15 == column_register:
                        assert earlier_word >> 12 == 3
                        struct.pack_into('<H', data, method['code'] + 16 + earlier_position * 2, (earlier_word & 0x0FFF) | 0x2000)
                        tv_columns += 1
                        break
    for method in dex.defined:
        if method['class'] != 'Lcom/android/vending/activities/MainActivity;' or method['name'] != 'onCreate':
            continue
        listing = list(instructions(dex, method))
        raw = dex.method_bytes(method)
        recent_strings = []
        for position, word, size in listing:
            opcode = word & 255
            if opcode in (0x1A, 0x1B):
                string_id = struct.unpack_from('<H' if opcode == 0x1A else '<I', raw, position * 2 + 2)[0]
                recent_strings.append((position, dex.strings[string_id]))
            if opcode in (0x72, 0x78):
                method_id = struct.unpack_from('<H', raw, position * 2 + 2)[0]
                called = dex.methods[method_id]
                if called['class'] == 'Landroid/content/SharedPreferences;' and called['name'] == 'getBoolean' and any(text == 'dialog_alert' and position - at < 20 for at, text in recent_strings):
                    result = struct.unpack_from('<H', raw, (position + size) * 2)[0]
                    assert result & 255 == 0x0A, 'Expected boolean move-result'
                    register = result >> 8
                    # Substitute a constant false for this preference result, leaving instruction addresses intact.
                    replacement = struct.pack('<4H', 0x13 | (register << 8), 0, 0, 0)
                    start = method['code'] + 16 + position * 2
                    data[start:start + 8] = replacement
                    popup_patches.append({'method': method['index'], 'codeUnit': position, 'resultRegister': register})
            if opcode == 0x15 and struct.unpack_from('<H', raw, position * 2 + 2)[0] == 0xFFFF:
                # The activity's red progress indicator becomes white; const/16 is the same instruction width.
                start = method['code'] + 16 + position * 2
                struct.pack_into('<HH', data, start, (word & 0xFF00) | 0x13, 0xFFFF)
                progress_colors += 1
    package_strings = 0
    for index, text in enumerate(dex.strings):
        if text == OLD_PACKAGE or any(text.lower().startswith((OLD_PACKAGE + suffix).lower()) for suffix in AUTHORITY_SUFFIXES):
            replacement = NEW_PACKAGE + text[len(OLD_PACKAGE):]
            assert len(replacement.encode()) == len(text.encode())
            cursor = dex.u32(dex.u32(60) + index * 4)
            _, cursor = dex.uleb(cursor)
            encoded = replacement.encode('utf-8')
            data[cursor:cursor + len(encoded)] = encoded
            package_strings += 1
    data[12:32] = hashlib.sha1(data[32:]).digest()
    struct.pack_into('<I', data, 8, zlib.adler32(data[12:]) & 0xFFFFFFFF)
    path.write_bytes(data)
    return {'dex': path.name, 'telegramPopupPreferenceOverrides': popup_patches, 'progressColorsNeutralized': progress_colors, 'packageIdentityStringsUpdated': package_strings, 'namedSportFilters': sport_labels, 'tvGridColumnUpdates': tv_columns}


def main(project):
    project = Path(project)
    reports = []
    with zipfile.ZipFile(ROOT / 'CRICFy_v7.3.apk') as source:
        for name in ('classes.dex', 'classes2.dex'):
            path = project / name
            path.write_bytes(source.read(name))
            reports.append(edit_dex(path))
    assert sum(len(item['telegramPopupPreferenceOverrides']) for item in reports) == 1, 'Expected exactly one Telegram popup trigger'
    assert sum(len(item['namedSportFilters']) for item in reports) == 1, 'Expected exactly one sport-label binding'
    assert sum(item['tvGridColumnUpdates'] for item in reports) == 1, 'Expected exactly one TV grid layout'
    report = {'package': NEW_PACKAGE, 'telegramPopupDisabledAtTrigger': True, 'nativeSignerLogicModifiedByThisScript': False, 'dexEdits': reports}
    (ROOT / 'analysis/app-code-edits.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('project')
    main(parser.parse_args().project)
