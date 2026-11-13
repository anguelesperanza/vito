#!/usr/bin/env python3
"""Compile Cg shaders to the .gxp programs SceGxm runs.

    python tools/build_shaders.py <folder> [<folder> ...]
    python tools/build_shaders.py            (every shader folder in the repo)

In each folder, every NAME_v.cg is compiled as a vertex program and every
NAME_f.cg as a fragment program, to NAME_v.gxp / NAME_f.gxp next to it.
A shader whose .gxp is newer than its source is skipped (--force rebuilds).

The compiler is Sony's psp2cgc.exe, which is proprietary and is NOT in this
repository: put your own copy at tools/psp2cgc.exe (it is git-ignored), or
set the PSP2CGC environment variable to its path. The compiled .gxp files
ARE checked in, so the compiler is only needed to change a shader.
"""
import glob
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
PROFILES = {"_v.cg": "sce_vp_psp2", "_f.cg": "sce_fp_psp2"}


def compiler():
    path = os.environ.get("PSP2CGC") or os.path.join(HERE, "psp2cgc.exe")
    if not os.path.isfile(path):
        sys.exit(f"psp2cgc.exe not found at {path}\n"
                 "Put a copy at tools/psp2cgc.exe or set PSP2CGC. It is not needed "
                 "unless a .cg file changed: the .gxp files are in the repository.")
    return path


def build(folder, force):
    failed = 0
    sources = sorted(glob.glob(os.path.join(folder, "*.cg")))
    if not sources:
        print(f"{folder}: no .cg files")
    for source in sources:
        profile = next((p for suffix, p in PROFILES.items() if source.endswith(suffix)), None)
        if profile is None:
            print(f"skip   {source} (name must end in _v.cg or _f.cg)")
            continue
        output = source[:-3] + ".gxp"
        if not force and os.path.exists(output) and os.path.getmtime(output) >= os.path.getmtime(source):
            print(f"ok     {output}")
            continue
        result = subprocess.run([compiler(), "-profile", profile, "-W4", "-nocolor", "-o", output, source],
                                capture_output=True, text=True)
        messages = (result.stdout + result.stderr).strip()
        if result.returncode != 0:
            failed += 1
            print(f"FAILED {source}\n{messages}")
        else:
            print(f"built  {output} ({os.path.getsize(output)} bytes)")
            if messages:
                print(messages)
    return failed


def main():
    args = [a for a in sys.argv[1:] if a != "--force"]
    force = "--force" in sys.argv
    folders = args or sorted({os.path.dirname(p) for p in
                              glob.glob(os.path.join(ROOT, "lib", "**", "*.cg"), recursive=True) +
                              glob.glob(os.path.join(ROOT, "Examples", "**", "*.cg"), recursive=True)})
    failed = sum(build(folder, force) for folder in folders)
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
