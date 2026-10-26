"""Remove invalid, unreachable array payload trailers from analysis copies only."""
import argparse
import hashlib
import json
import struct
import zlib
from pathlib import Path
from inspect_apk import Dex


WIDTH = [1] * 256
for opcode in (0x02, 0x05, 0x08, 0x13, 0x15, 0x16, 0x19, 0x1A, 0x1C, 0x1F, 0x20, 0x22, 0x23, 0x29, 0xFE, 0xFF):
    WIDTH[opcode] = 2
for opcode in (0x03, 0x06, 0x09, 0x14, 0x17, 0x1B, 0x24, 0x25, 0x26, 0x2A, 0x2B, 0x2C, 0xFC, 0xFD):
    WIDTH[opcode] = 3
WIDTH[0x18] = 5
WIDTH[0xFA] = WIDTH[0xFB] = 4
for start, end, size in ((0x2D,0x3E,2),(0x44,0x6E,2),(0x6E,0x73,3),(0x74,0x79,3),(0x90,0xB0,2),(0xD0,0xE3,2)):
    for opcode in range(start, end):
        WIDTH[opcode] = size


def readable_copy(source, output):
    dex = Dex(source)
    data = bytearray(dex.data)
    changed = []
    for method in dex.defined:
        if not method['code']:
            continue
        start, count = method['code'] + 16, method['units']
        cursor = 0
        while cursor < count:
            word = struct.unpack_from('<H', data, start + cursor * 2)[0]
            if word == 0x0300:
                element_width = struct.unpack_from('<H', data, start + cursor * 2 + 2)[0]
                elements = struct.unpack_from('<I', data, start + cursor * 2 + 4)[0]
                if element_width not in (1, 2, 4, 8):
                    if element_width not in range(3, 32, 2) or count - cursor > 160:
                        raise ValueError(f'Unexpected trailer in {method}')
                    data[start + cursor * 2:start + count * 2] = b'\0' * ((count - cursor) * 2)
                    changed.append({'index': method['index'], 'class': method['class'], 'name': method['name'], 'trailer_unit': cursor, 'trailer_units': count - cursor})
                    break
                cursor += 4 + (element_width * elements + 1) // 2
            elif word in (0x0100, 0x0200):
                size = struct.unpack_from('<H', data, start + cursor * 2 + 2)[0]
                cursor += 4 + size * 2 if word == 0x0100 else 2 + size * 4
            else:
                cursor += WIDTH[word & 255]
    data[12:32] = hashlib.sha1(data[32:]).digest()
    struct.pack_into('<I', data, 8, zlib.adler32(data[12:]) & 0xFFFFFFFF)
    output = Path(output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(data)
    output.with_suffix('.trailers.json').write_text(json.dumps(changed, indent=2), encoding='utf-8')
    print(f'Created analysis copy {output.name}: cleaned {len(changed)} unreachable trailers')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('source')
    parser.add_argument('output')
    args = parser.parse_args()
    readable_copy(args.source, args.output)
