"""Read-only DEX and ELF inspection helpers for this APK workspace."""
import argparse
import io
import json
import re
import struct
from pathlib import Path


class Dex:
    def __init__(self, path):
        self.path = Path(path)
        self.data = self.path.read_bytes()
        if not self.data.startswith(b'dex\n'):
            raise ValueError('Not a DEX file')
        self.strings = []
        count, offset = self.u32(56), self.u32(60)
        for index in range(count):
            cursor = self.u32(offset + index * 4)
            _, cursor = self.uleb(cursor)
            end = self.data.index(0, cursor)
            self.strings.append(self.data[cursor:end].decode('utf-8', errors='replace'))
        self.types = [self.strings[self.u32(self.u32(68) + index * 4)] for index in range(self.u32(64))]
        self.protos = []
        for index in range(self.u32(72)):
            pos = self.u32(76) + index * 12
            params = self.u32(pos + 8)
            arguments = [] if not params else [self.types[self.u16(params + 4 + i * 2)] for i in range(self.u32(params))]
            self.protos.append('(' + ''.join(arguments) + ')' + self.types[self.u32(pos + 4)])
        self.methods = []
        for index in range(self.u32(88)):
            pos = self.u32(92) + index * 8
            owner = self.types[self.u16(pos)]
            name = self.strings[self.u32(pos + 4)]
            self.methods.append({'index': index, 'class': owner, 'name': name, 'proto': self.protos[self.u16(pos + 2)]})
        self.defined = []
        for index in range(self.u32(96)):
            pos = self.u32(100) + index * 32
            cursor = self.u32(pos + 24)
            if not cursor:
                continue
            counts = []
            for _ in range(4):
                value, cursor = self.uleb(cursor)
                counts.append(value)
            for _ in range(counts[0] + counts[1]):
                _, cursor = self.uleb(cursor)
                _, cursor = self.uleb(cursor)
            for count in counts[2:]:
                method_id = 0
                for _ in range(count):
                    delta, cursor = self.uleb(cursor)
                    method_id += delta
                    access, cursor = self.uleb(cursor)
                    code, cursor = self.uleb(cursor)
                    entry = dict(self.methods[method_id], access=access, code=code)
                    if code:
                        entry.update(registers=self.u16(code), ins=self.u16(code + 2), tries=self.u16(code + 6), units=self.u32(code + 12))
                    self.defined.append(entry)

    def u16(self, offset):
        return struct.unpack_from('<H', self.data, offset)[0]

    def u32(self, offset):
        return struct.unpack_from('<I', self.data, offset)[0]

    def uleb(self, offset):
        result = shift = 0
        while True:
            value = self.data[offset]
            offset += 1
            result |= (value & 127) << shift
            if not value & 128:
                return result, offset
            shift += 7
            if shift > 35:
                raise ValueError('Invalid ULEB128')

    def method_bytes(self, method):
        start = method['code'] + 16
        return self.data[start:start + method.get('units', 0) * 2]


def inspect_dex(args):
    dex = Dex(args.path)
    matches = []
    pattern = re.compile(args.pattern or 'MainActivity|Baker|tg|telegram', re.I)
    for method in dex.defined:
        raw = dex.method_bytes(method) if method['code'] else b''
        literal_match = args.literal is not None and struct.pack('<I', int(args.literal, 0)) in raw
        if not literal_match and not pattern.search(method['class'] + '->' + method['name']):
            continue
        entry = dict(method)
        entry['first_bytes'] = raw[:48].hex(' ')
        entry['tail_bytes'] = raw[-32:].hex(' ')
        if args.literal is not None:
            needle = struct.pack('<I', int(args.literal, 0))
            entry['literal_offsets'] = [i // 2 for i in range(len(raw) - 3) if raw[i:i + 4] == needle]
        matches.append(entry)
    output = {'file': str(dex.path), 'defined_methods': len(dex.defined), 'matches': matches}
    text = json.dumps(output, indent=2)
    if args.output:
        Path(args.output).write_text(text, encoding='utf-8')
        print(f'Wrote {len(matches)} method records to {args.output}')
    else:
        print(text)


def inspect_elf(args):
    from elftools.elf.elffile import ELFFile
    import capstone
    raw = Path(args.path).read_bytes()
    elf = ELFFile(io.BytesIO(raw))
    machine = elf['e_machine']
    if machine == 'EM_X86_64':
        disasm = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
    elif machine == 'EM_386':
        disasm = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_32)
    elif machine == 'EM_AARCH64':
        disasm = capstone.Cs(capstone.CS_ARCH_ARM64, capstone.CS_MODE_ARM)
    else:
        disasm = capstone.Cs(capstone.CS_ARCH_ARM, capstone.CS_MODE_THUMB)
    symbols = []
    by_address = {}
    for section in elf.iter_sections():
        if section['sh_type'] in ('SHT_DYNSYM', 'SHT_SYMTAB'):
            for symbol in section.iter_symbols():
                if symbol['st_value']:
                    by_address[symbol['st_value'] & ~1 if machine == 'EM_ARM' else symbol['st_value']] = symbol.name
                symbols.append(symbol)
    plt = elf.get_section_by_name('.plt')
    rela = elf.get_section_by_name('.rela.plt') or elf.get_section_by_name('.rel.plt')
    if plt and rela:
        table = elf.get_section(rela['sh_link'])
        start = 32 if machine == 'EM_AARCH64' else 16
        for index, rel in enumerate(rela.iter_relocations()):
            by_address[plt['sh_addr'] + start + index * 16] = table.get_symbol(rel['r_info_sym']).name + '@plt'
    pattern = re.compile(args.pattern or 'Baker_merge|AntiTamper10isTampered|AesDecrypt_decrypt')
    if args.address:
        address = int(args.address, 0)
        section_index = next(index for index, section in enumerate(elf.iter_sections()) if section['sh_addr'] <= address < section['sh_addr'] + section['sh_size'] and section['sh_type'] != 'SHT_NOBITS')
        symbols = [{'name': '<address>', 'st_value': address, 'st_size': int(args.size, 0), 'st_shndx': section_index}]
        pattern = re.compile('.')
    lines = []
    seen = set()
    for symbol in symbols:
        name = symbol['name'] if isinstance(symbol, dict) else symbol.name
        if not pattern.search(name) or not symbol['st_value'] or name in seen:
            continue
        seen.add(name)
        address = symbol['st_value'] & ~1 if machine == 'EM_ARM' else symbol['st_value']
        section = elf.get_section(symbol['st_shndx'])
        offset = section['sh_offset'] + address - section['sh_addr']
        lines.append(f'\n{name} va=0x{address:x} file=0x{offset:x} size={symbol["st_size"]}')
        for insn in disasm.disasm(raw[offset:offset + symbol['st_size']], address):
            note = ''
            target = re.fullmatch(r'0x([0-9a-fA-F]+)', insn.op_str)
            if target and insn.mnemonic in ('call', 'jmp', 'bl', 'b'):
                note = ' ; ' + by_address.get(int(target[1], 16), '')
            lines.append(f'{insn.address:08x}: {insn.mnemonic:9} {insn.op_str}{note}')
    text = '\n'.join(lines)
    if args.output:
        Path(args.output).write_text(text, encoding='utf-8')
        print(f'Wrote {len(seen)} functions to {args.output}')
    else:
        print(text)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('kind', choices=['dex', 'elf'])
    parser.add_argument('path')
    parser.add_argument('--pattern')
    parser.add_argument('--literal')
    parser.add_argument('--output')
    parser.add_argument('--address')
    parser.add_argument('--size', default='1024')
    arguments = parser.parse_args()
    (inspect_dex if arguments.kind == 'dex' else inspect_elf)(arguments)
