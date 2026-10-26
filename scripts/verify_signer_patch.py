"""Verify that preview signing changes only the pinned public certificate digest."""
import hashlib
import argparse
import io
import json
import zipfile
from pathlib import Path
from elftools.elf.elffile import ELFFile
from native_signer_info import signer_certificate

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--apk', help='Inspect a built proposal instead of decoded native files')
args = parser.parse_args()
preview = zipfile.ZipFile(args.apk) if args.apk else None
old = hashlib.sha256(signer_certificate(root / 'CRICFy_v7.3.apk')).digest()
new = hashlib.sha256((root / '.tools/keys/cricfy-ui-test.cer').read_bytes()).digest()
records = []
with zipfile.ZipFile(root / 'CRICFy_v7.3.apk') as archive:
    for abi in ('arm64-v8a', 'armeabi-v7a', 'x86', 'x86_64'):
        path = f'lib/{abi}/libnative-lib.so'
        original = archive.read(path)
        modified = preview.read(path) if preview else (root / 'decoded' / path).read_bytes()
        assert len(original) == len(modified)
        intervals = []
        expected = bytearray(original)
        for part in range(2):
            pin = old[part * 16:part * 16 + 16]
            assert original.count(pin) == 1
            offset = original.index(pin)
            expected[offset:offset + 16] = new[part * 16:part * 16 + 16]
            intervals.append([offset, offset + 16])
        assert modified == expected, f'Unexpected byte changes in {abi}'
        elf = ELFFile(io.BytesIO(original))
        executable_sections = []
        for section in elf.iter_sections():
            if section['sh_flags'] & 4:
                begin = section['sh_offset']
                end = begin + section['sh_size']
                executable_sections.append({'section': section.name, 'byteIdentical': original[begin:end] == modified[begin:end], 'containsCertificateLiteralPool': any(begin <= lo < end for lo, hi in intervals)})
        gates = []
        for section in elf.iter_sections():
            if section['sh_type'] == 'SHT_DYNSYM':
                for symbol in section.iter_symbols():
                    if symbol.name in ('_ZN7apk_sig6verifyEP7_JNIEnvP8_jobject', '_ZN10AntiTamper10isTamperedEP7_JNIEnvP8_jobject', 'Java_com_android_vending_networking_Baker_merge'):
                        code_section = elf.get_section(symbol['st_shndx'])
                        address = symbol['st_value'] & ~1 if abi == 'armeabi-v7a' else symbol['st_value']
                        lo = code_section['sh_offset'] + address - code_section['sh_addr']
                        hi = lo + symbol['st_size']
                        assert original[lo:hi] == modified[lo:hi], f'Native gate function changed: {abi} {symbol.name}'
                        gates.append({'name': symbol.name, 'byteIdentical': True})
        assert len(gates) == 3
        records.append({'abi': abi, 'pinIntervals': intervals, 'changedBytes': sum(a != b for a, b in zip(original, modified)), 'allNonFingerprintBytesIdentical': True, 'nativeGateFunctions': gates, 'executableSections': executable_sections})
report = {
    'apk': args.apk,
    'apkSha256': hashlib.sha256(Path(args.apk).read_bytes()).hexdigest() if args.apk else None,
    'change': 'Replace the vendor certificate digest with the local preview certificate digest',
    'originalCertificateSha256': old.hex(),
    'previewCertificateSha256': new.hex(),
    'trustedSignerCountBefore': 1,
    'trustedSignerCountAfter': 1,
    'wildcardSignerAcceptance': False,
    'changesOutsidePinnedFingerprint': False,
    'nativeGateFunctionsByteIdentical': True,
    'arm32LiteralPoolNote': 'The ARMv7 compiler places the 32-byte certificate constant in a literal pool within .text; these are certificate data bytes, not replaced gate functions.',
    'sha256ComparisonStillEnabled': True,
    'androidPackageSignatureVerificationStillEnabled': True,
    'fridaAndEnvironmentChecksChanged': False,
    'libraries': records,
}
destination = root / 'analysis/native-signer-scope-verification.json'
destination.write_text(json.dumps(report, indent=2), encoding='utf-8')
print(json.dumps({key: value for key, value in report.items() if key != 'libraries'}, indent=2))
print(f'Verified all four ABIs; details: {destination}')
