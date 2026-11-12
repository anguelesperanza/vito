#!/usr/bin/env python3
"""Regenerate lib/libm/redefine.syms.

    python tools/gen_libm_syms.py      (from the repo root)

build.bat renames these symbols inside the Odin object only
(objcopy --redefine-syms), from `name` to `vito_name`.

Why every name and not just the bridged ones: all of these functions take or
return float/double, and VitaSDK's copies expect them in VFP registers while
Odin passes them in integer registers. A direct call links and silently returns
garbage. With the rename, a function that lib/libm/bridge.c does not wrap fails
at link time with "undefined reference to `vito_<name>'", which says exactly
what to add to bridge.c.

The list is: every public function in newlib's libm.a, plus the libgcc helpers
LLVM calls for float <-> 64-bit integer conversion and friends.
"""
import os
import re
import subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, ".."))
VITASDK = os.environ.get("VITASDK", r"C:\vitasdk")
NM = os.path.join(VITASDK, "bin", "arm-vita-eabi-nm")
LIBM = os.path.join(VITASDK, "arm-vita-eabi", "lib", "libm.a")

# libgcc routines with a float or double argument or result.
LIBGCC = """__fixdfdi __fixsfdi __fixunsdfdi __fixunssfdi __floatdidf __floatdisf __floatundidf
__floatundisf __fixdfsi __fixsfsi __fixunsdfsi __fixunssfsi __floatsidf __floatsisf __floatunsidf
__floatunsisf __extendsfdf2 __truncdfsf2 __powidf2 __powisf2 __muldc3 __mulsc3 __divdc3 __divsc3
__gnu_h2f_ieee __gnu_f2h_ieee __gnu_d2h_ieee __extendhfsf2 __truncsfhf2 __truncdfhf2""".split()

# fenv functions only take integers and pointers: safe to call directly.
SKIP = re.compile(r"^(fe[a-z]+|_.*)$")


def main():
    out = subprocess.run([NM, LIBM], capture_output=True, text=True).stdout
    names = set()
    for ln in out.splitlines():
        m = re.match(r"^[0-9a-f]+ [TW] (\w+)$", ln)
        if m and not SKIP.match(m.group(1)):
            names.add(m.group(1))
    names = sorted(names) + LIBGCC
    path = os.path.join(ROOT, "lib", "libm", "redefine.syms")
    with open(path, "w", newline="\n") as f:
        for n in names:
            f.write(f"{n} vito_{n}\n")
    print(f"{len(names)} symbols -> {path}")


if __name__ == "__main__":
    main()
