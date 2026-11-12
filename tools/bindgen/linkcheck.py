#!/usr/bin/env python3
"""Link check for the generated `sce` bindings.

    python tools/bindgen/linkcheck.py      (from the repo root, after gen.py)

Builds a throwaway program that takes the address of EVERY bound function,
compiles lib/sce/bridge.c, and links it against every stub library the
bindings name. It passes only if every function resolves to a real symbol.
It also runs the two ABI checks from docs/getting-started.md on the object.

Nothing here runs on a Vita: this proves the names, link libraries and the
float bridge are right, not that each call behaves correctly.
"""
import glob
import os
import re
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
WORK = os.path.join(HERE, "work", "linkcheck")
SCE = os.path.join(ROOT, "lib", "sce")
VITASDK = os.environ.get("VITASDK", r"C:\vitasdk")
BIN = os.path.join(VITASDK, "bin")
ARCH = ["-march=armv7-a", "-mtune=cortex-a9", "-mfpu=neon", "-mfloat-abi=hard"]


def tool(n):
    return os.path.join(BIN, n)


def run(cmd, cwd=None):
    r = subprocess.run(cmd, capture_output=True, text=True, cwd=cwd)
    if r.returncode != 0:
        sys.stdout.write(r.stdout[-3000:])
        sys.stdout.write(r.stderr[-6000:])
        raise SystemExit("FAILED: " + " ".join(os.path.basename(c) for c in cmd[:3]))
    return r.stdout


def main():
    funcs, libs = [], set()
    for p in sorted(glob.glob(os.path.join(SCE, "*.odin"))):
        txt = open(p, encoding="utf-8").read()
        for m in re.finditer(r'foreign import \w+ "system:(\w+)"', txt):
            if m.group(1) != "sce_bridge":
                libs.add(m.group(1))
        for m in re.finditer(r'^    (?:@\(link_name = "\w+"\) )?(\w+) :: proc\(.*---$', txt, re.M):
            funcs.append(m.group(1))
    funcs = sorted(set(funcs))

    shutil.rmtree(WORK, ignore_errors=True)
    os.makedirs(WORK)
    rel = os.path.relpath(SCE, WORK).replace("\\", "/")
    src = f'package linkcheck\n\nimport sce "{rel}"\n\n@(export, link_name = "odin_main")\n'
    src += 'odin_main :: proc "c" (argc: i32, argv: [^]cstring) -> i32 {\n    table := [?]rawptr{\n'
    for f in funcs:
        src += f"        rawptr(sce.{f}),\n"
    src += "    }\n    sum: uintptr\n    for p in table do sum += uintptr(p)\n    return i32(sum)\n}\n"
    open(os.path.join(WORK, "main.odin"), "w", newline="\n").write(src)
    open(os.path.join(WORK, "main.c"), "w").write(
        "extern int odin_main(int argc, char* argv[]);\nint main(int argc, char* argv[]) { return odin_main(argc, argv); }\n")

    run(["odin", "build", ".", "-target:freestanding_arm32", "-o:speed", "-build-mode:asm", "-no-entry-point",
         "-min-link-libs", "-no-thread-local", "-microarch:cortex-a9"], cwd=WORK)
    asm = glob.glob(os.path.join(WORK, "*.S"))[0]
    obj = os.path.join(WORK, "odin.o")
    run([tool("arm-vita-eabi-gcc"), "-c", "-x", "assembler", asm, "-o", obj, *ARCH])
    run([tool("arm-vita-eabi-objcopy"), "--remove-section", ".ARM.attributes",
         "--redefine-syms=" + os.path.join(ROOT, "lib", "libm", "redefine.syms"), obj])
    objs = [obj]
    for name, c in (("main", os.path.join(WORK, "main.c")), ("sce_bridge", os.path.join(SCE, "bridge.c")),
                    ("libm_bridge", os.path.join(ROOT, "lib", "libm", "bridge.c"))):
        o = os.path.join(WORK, name + ".o")
        run([tool("arm-vita-eabi-gcc"), "-c", c, "-o", o, *ARCH, "-Wall", "-Werror"])
        objs.append(o)
    elf = os.path.join(WORK, "linkcheck.elf")
    run([tool("arm-vita-eabi-gcc"), "-o", elf, *objs, *ARCH, "-Wl,-q", *["-l" + l for l in sorted(libs)], "-lm"])

    undef = run([tool("arm-vita-eabi-nm"), "-u", obj]).split()
    undef = [u for u in undef if u != "U"]
    libm = set(l.split()[0] for l in open(os.path.join(ROOT, "lib", "libm", "redefine.syms")).read().splitlines() if l.strip())
    stray = [u for u in undef if u in libm]
    asm_txt = open(asm).read()
    bad_ins = re.findall(r"^\s+(mcr)\b.*$", asm_txt, re.M)
    print(f"linked {len(funcs)} functions against {len(libs)} stub libraries: OK")
    print("stray libm calls in the Odin object:", stray or "none")
    print("CP15 barrier (mcr) instructions in the Odin assembly:", len(bad_ins))
    if stray or bad_ins:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
