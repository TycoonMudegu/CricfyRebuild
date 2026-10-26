"""Inspect the public signer certificate and the native signer's expected fingerprint."""
import hashlib
import io
import json
import struct
import sys
from pathlib import Path
from elftools.elf.elffile import ELFFile


def signer_certificate(path):
    raw = Path(path).read_bytes()
    eocd = raw.rfind(b'PK\x05\x06')
    central = struct.unpack_from('<I', raw, eocd + 16)[0]
    assert raw[central - 16:central] == b'APK Sig Block 42'
    block_size = struct.unpack_from('<Q', raw, central - 24)[0]
    cursor = central - block_size - 8 + 8
    while cursor < central - 24:
        length = struct.unpack_from('<Q', raw, cursor)[0]
        tag = struct.unpack_from('<I', raw, cursor + 8)[0]
        value = raw[cursor + 12:cursor + 8 + length]
        if tag == 0x7109871A:
            break
        cursor += 8 + length
    else:
        raise ValueError('APK v2 signer not found')

    def read_lp(buffer, position=0):
        size = struct.unpack_from('<I', buffer, position)[0]
        return buffer[position + 4:position + 4 + size], position + 4 + size

    signers, _ = read_lp(value)
    signer, _ = read_lp(signers)
    signed_data, _ = read_lp(signer)
    _, cursor = read_lp(signed_data)
    certificates, _ = read_lp(signed_data, cursor)
    certificate, _ = read_lp(certificates)
    return certificate


def fnv1a(data, basis=0xCBF29CE484222325):
    value = basis
    for byte in data:
        value = ((value ^ byte) * 0x100000001B3) & 0xFFFFFFFFFFFFFFFF
    return value


def elf_offset(elf, address):
    for section in elf.iter_sections():
        if section['sh_type'] != 'SHT_NOBITS' and section['sh_addr'] <= address < section['sh_addr'] + section['sh_size']:
            return section['sh_offset'] + address - section['sh_addr']
    raise ValueError(f'Unmapped address {address:x}')


if __name__ == '__main__':
    for path in sys.argv[1:]:
        certificate = signer_certificate(path)
        print(json.dumps({'apk': path, 'certificateBytes': len(certificate), 'sha256': hashlib.sha256(certificate).hexdigest(), 'sha1': hashlib.sha1(certificate).hexdigest(), 'fnv1a': hex(fnv1a(certificate))}))
    root = Path(__file__).resolve().parents[1]
    path = root / 'decoded/lib/x86_64/libnative-lib.so'
    raw = path.read_bytes()
    elf = ELFFile(io.BytesIO(raw))
    address = 0x61D67 + 0x80939
    offset = elf_offset(elf, address)
    encoded = struct.unpack_from('<Q', raw, offset)[0]
    print(json.dumps({'nativeExpectedAddress': hex(address), 'fileOffset': hex(offset), 'encoded': hex(encoded), 'expectedFingerprint': hex(encoded ^ 0x5A5A5A5A12345678)}))
