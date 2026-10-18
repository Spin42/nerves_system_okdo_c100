#!/usr/bin/env python3
"""Find where an aarch64 process crashed from its ELF core dump.

Prints pc and lr of the first thread as <library>+<file offset>, plus
return-address candidates found by scanning the stack. Each line is
"<label> <path> <offset>"; resolve offsets with addr2line against the
unstripped library in the Nerves system's staging directory. Useful when
the toolchain's gdb cannot load the core.

Usage: corepc.py <core>
"""
import struct
import sys

data = open(sys.argv[1], "rb").read()
assert data[:4] == b"\x7fELF" and data[4] == 2, "not a 64-bit ELF"
(e_phoff,) = struct.unpack_from("<Q", data, 0x20)
e_phentsize, e_phnum = struct.unpack_from("<HH", data, 0x36)

notes, loads = [], []
for i in range(e_phnum):
    p_type, _flags, p_offset, p_vaddr, _paddr, p_filesz, p_memsz, _align = \
        struct.unpack_from("<IIQQQQQQ", data, e_phoff + i * e_phentsize)
    if p_type == 4:
        notes.append((p_offset, p_filesz))
    elif p_type == 1:
        loads.append((p_vaddr, p_memsz, p_offset, p_filesz))

prstatus, files = [], None
for off, size in notes:
    pos = off
    while pos < off + size:
        namesz, descsz, ntype = struct.unpack_from("<III", data, pos)
        pos += 12
        pos += (namesz + 3) & ~3
        desc = data[pos:pos + descsz]
        pos += (descsz + 3) & ~3
        if ntype == 1:
            prstatus.append(desc)
        elif ntype == 0x46494C45:
            files = desc

count, page = struct.unpack_from("<QQ", files, 0)
entries = [struct.unpack_from("<QQQ", files, 16 + 24 * i) for i in range(count)]
names = files[16 + 24 * count:].split(b"\0")[:count]
maps = [(s, e, o * page, n.decode()) for (s, e, o), n in zip(entries, names)]


def where(addr):
    for s, e, foff, name in maps:
        if s <= addr < e:
            return name, addr - s + foff
    return None


def read_mem(addr, n):
    for vaddr, memsz, foff, filesz in loads:
        if vaddr <= addr and addr + n <= vaddr + filesz:
            start = foff + addr - vaddr
            return data[start:start + n]
    return None


regs = struct.unpack_from("<34Q", prstatus[0], 112)
pc, lr, sp = regs[32], regs[30], regs[31]
for label, addr in (("pc", pc), ("lr", lr)):
    w = where(addr)
    print(label, *(w if w else ("?", hex(addr))))

seen = 0
for i in range(4096):
    word = read_mem(sp + 8 * i, 8)
    if word is None:
        break
    (val,) = struct.unpack("<Q", word)
    w = where(val)
    if w and w[0].startswith("/"):
        print("stack", *w)
        seen += 1
        if seen >= 25:
            break
