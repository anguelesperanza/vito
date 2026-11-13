#!/usr/bin/env python3
"""Print what is understood of a compiled shader (.gxp).

    python tools/gxp_info.py <file.gxp> [<file.gxp> ...]
    python tools/gxp_info.py            (every .gxp in the repo)

The layout it decodes is described in docs/gxp-format.md. Only fields that
have been checked against this repository's own shaders are named; the rest
of the header is printed as raw words.
"""
import glob
import os
import struct
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

CATEGORIES = {0: "attribute", 1: "uniform", 2: "sampler"}


def u8(d, o):  return d[o]
def u16(d, o): return struct.unpack_from("<H", d, o)[0]
def u32(d, o): return struct.unpack_from("<I", d, o)[0]


def cstring(d, o):
    end = d.index(b"\0", o)
    return d[o:end].decode("ascii", "replace")


def describe(path):
    d = open(path, "rb").read()
    print(f"== {os.path.relpath(path, ROOT)} ({len(d)} bytes)")
    if d[:4] != b"GXP\0":
        print("   not a GXP file")
        return
    flags = u32(d, 0x14)
    print(f"   version {u8(d, 4)}.{u8(d, 5)}   sdk 0x{u16(d, 6):04X}   size field {u32(d, 8)}")
    print(f"   hashes 0x{u32(d, 0x0C):08X} 0x{u32(d, 0x10):08X}")
    print(f"   flags 0x{flags:08X} ({'fragment' if flags & 1 else 'vertex'} program)")
    print(f"   texture unit mask 0x{u32(d, 0x1C):08X}")
    print(f"   register words: primary {u16(d, 0x30)} (attributes / varyings in), secondary {u16(d, 0x32)} (uniforms)")
    print(f"   default uniform buffer: {u32(d, 0x64)} floats")

    count = u32(d, 0x24)
    table = 0x28 + u32(d, 0x28)
    print(f"   {count} parameters, table at 0x{table:X}")
    for i in range(count):
        entry = table + i * 16
        name = cstring(d, entry + u32(d, entry))
        bits = u16(d, entry + 4)
        category, type_, components, container = bits & 15, bits >> 4 & 15, bits >> 8 & 15, bits >> 12 & 15
        print(f"      {name:<18} {CATEGORIES.get(category, category):<9} type {type_} components {components} "
              f"container {container:<2} semantic {u8(d, entry + 6)}/{u8(d, entry + 7)} "
              f"array {u32(d, entry + 8)} resource index {u32(d, entry + 12)}")

    instructions = u32(d, 0x3C)
    code = 0x40 + u32(d, 0x40)
    print(f"   code: {instructions} instructions of 8 bytes at 0x{code:X}")
    for i in range(instructions):
        o = code + i * 8
        if o + 8 > len(d):
            break
        print(f"      {u32(d, o):08X} {u32(d, o + 4):08X}")

    print("   header words not named above:")
    named = {0x00, 0x04, 0x08, 0x0C, 0x10, 0x14, 0x1C, 0x24, 0x28, 0x30, 0x3C, 0x40, 0x64}
    words = [f"0x{o:02X}={u32(d, o):08X}" for o in range(0, min(code, len(d)) - 3, 4) if o not in named and u32(d, o)]
    for i in range(0, len(words), 6):
        print("      " + "  ".join(words[i:i + 6]))


def main():
    paths = sys.argv[1:] or sorted(glob.glob(os.path.join(ROOT, "**", "*.gxp"), recursive=True))
    for path in paths:
        describe(path)


if __name__ == "__main__":
    main()
