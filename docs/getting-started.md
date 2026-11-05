# Getting started

How to build a PS Vita `.vpk` from Odin source on Windows with `build.bat`.

Only things that were run and worked are listed here. Anything not yet tested is
under [Not verified](#not-verified).

**Tested with:** Windows 11, Odin `dev-2026-11:e28f5d1ff`, VitaSDK `2026.08`
(`arm-vita-eabi-gcc` 15.2.0), Vita3K v0.2.1, and a hacked PS Vita.
The template and the vita2d example were run on the emulator **and** on real
hardware. The touch example was run on real hardware only.

---

## 1. Install VitaSDK

Use the official `vdpm` bootstrap. Run it with **PowerShell 7 (`pwsh`)**. Windows
PowerShell 5.1 fails with
`[System.IO.Path] does not contain a method named 'IsPathFullyQualified'`.

```
git clone https://github.com/vitasdk/vdpm
cd vdpm
pwsh -NoProfile -ExecutionPolicy Bypass -File .\bootstrap-vitasdk.ps1
```

This installs VitaSDK to `C:\vitasdk`. The toolchain is in `C:\vitasdk\bin`
(`arm-vita-eabi-gcc`, `vita-elf-create`, `vita-make-fself`, `vita-mksfoex`,
`vita-pack-vpk`, `vdpm`). Stub libraries such as `libSceCtrl_stub.a` are in
`C:\vitasdk\arm-vita-eabi\lib`, and headers are in
`C:\vitasdk\arm-vita-eabi\include\psp2*`.

`build.bat` defaults to `C:\vitasdk`. To use another location, set `VITASDK`
before running it.

### Extra libraries (needed for the vita2d example)

`vdpm` needs `VITASDK` set to run. In PowerShell:

```
$env:VITASDK = 'C:\vitasdk'
$env:PATH = "C:\vitasdk\bin;$env:PATH"
vdpm search vita2d          # lists libvita2d
vdpm install libvita2d      # also installs freetype, libpng, libjpeg-turbo, zlib, bzip2
```

The installer prints "Can't create ... libpng.a" warnings on Windows because it
cannot create the symlink. They are harmless: `libpng16.a` is the real file and
`build.bat` links `-lpng16`.

## 2. Build and run

From **PowerShell or cmd** (not Git Bash, see [Gotchas](#gotchas)):

```
cd NewProjectTemplate        # framebuffer demo, no extra libraries
.\build.bat                  # -> MyGame.vpk

cd Examples\Vita2D-Example   # vita2d demo, needs libvita2d
.\build.bat                  # -> Vita2D-Example.vpk

cd Examples\Touch-Example    # front + back touch panels, drawn with vita2d
.\build.bat                  # -> Touch-Example.vpk
```

Settings at the top of each `build.bat`:

| Variable   | Meaning                                                           |
|------------|-------------------------------------------------------------------|
| `TARGET`   | Output name (`<TARGET>.vpk`)                                      |
| `TITLE_ID` | Exactly 9 characters: 4 letters then 5 digits                     |
| `TITLE`    | Name shown under the bubble                                       |
| `BRIDGES`  | Space-separated `lib\<name>\bridge.c` files to compile and link   |

**Vita3K:** *File → Install .vpk*, pick the `.vpk`, then start it. Its log window
shows the `sceClibPrintf` output.
**Real Vita:** install the `.vpk` with VitaShell.

Start exits every example. In the template and the vita2d example, the D-pad or
left stick moves things and Cross toggles a colour (and logs `CROSS pressed`).

| Project                   | Title ID    | What it shows                                                        |
|---------------------------|-------------|----------------------------------------------------------------------|
| `NewProjectTemplate`      | `ODIN00001` | Scrolling gradient + a movable white square (raw framebuffer)        |
| `Examples/Vita2D-Example` | `ODIN00002` | vita2d: rotating/scaling sprite, circles, line, text, tint           |
| `Examples/Touch-Example`  | `ODIN00003` | Front touches (cyan circles + trail), back touches (magenta squares), live coordinates. Cross clears the trail |

### Touch input

`lib/sce/touch.odin` binds `SceTouch` (link `-lSceTouch_stub`). All arguments are
integers, so it needs no float bridge.

- Start sampling per panel before reading: `sceTouchSetSamplingState(port, .START)`.
- Read with `sceTouchPeek(port, &data, 1)` (non-blocking). `data.reportNum` is the
  number of fingers; `data.report[i]` holds `id`, `force`, and `x`/`y`.
- `x`/`y` are **panel coordinates** (the front is about 1920x1088), not screen
  pixels. Convert with the active area from `sceTouchGetPanelInfo`:
  `screen = (raw - minAa) / (maxAa - minAa) * screen_size`. The example does this
  in `make_panel` / `to_screen`, with the known panel sizes as a fallback.
- The back panel has a different active area (about 1920x890), so use its own
  `sceTouchGetPanelInfo`, not the front's.

---

## How the pipeline works

```
main.odin
   │  odin build . -target:freestanding_arm32 -build-mode:asm -no-entry-point
   ▼                -min-link-libs -no-thread-local -o:speed
ARM assembly (.S)
   │  arm-vita-eabi-gcc -c  -march=armv7-a -mtune=cortex-a9 -mfpu=neon -mfloat-abi=hard
   ▼
Odin object (.o) ── arm-vita-eabi-objcopy
   │                  --remove-section .ARM.attributes
   │                  --redefine-syms=lib\libm\redefine.syms
   │   + main.c object (C entry point -> odin_main)
   │   + lib\<name>\bridge.c objects (float ABI bridges)
   ▼
arm-vita-eabi-gcc -Wl,-q  -lSceCtrl_stub -lSceDisplay_stub ... (+ -lvita2d ...)
   ▼
ELF  ── vita-elf-create ─► velf ── vita-make-fself -c ─► eboot.bin
                                   vita-mksfoex ───────► param.sfo
                                                          │
                  vita-pack-vpk -s param.sfo -b eboot.bin ▼
                                                      <TARGET>.vpk
```

- `main.c` defines `main()` and calls the Odin procedure exported with
  `@(export, link_name = "odin_main")`.
- Odin does not know the SCE libraries. Bindings use `foreign import
  "system:SceCtrl_stub"` and similar, which only documents the dependency; the
  libraries that are actually linked are the `-l...` flags in `build.bat`. The
  Vita resolves the real functions at load time.

## The float ABI (read this before binding anything with floats)

Odin's `freestanding_arm32` output uses the **soft-float calling convention**: an
`f32` argument is passed in an integer register (`r0`-`r3`, then the stack).
VitaSDK's libraries are compiled **hard-float**: they expect floats in `s0`,
`s1`, ... and return them in `s0`. Integer and pointer arguments are the same in
both, so only functions touching floats are affected. Calling them directly does
not fail to link or crash; it passes garbage silently.

There are two places this shows up, and both are handled:

1. **Library functions with float parameters** (vita2d). `lib/vita2d/bridge.c`
   has wrappers that take every float as `uint32_t`, convert with `u2f()` from
   `lib/bridge_utils.h`, and call the real function. In Odin the bridged
   procedures are declared with ordinary `f32` parameters and linked to the
   `vito_*` wrapper names with `@(link_name = ...)`. In the generated `.S` file
   the `f32` arguments land in `r0`-`r3` and on the stack, which is exactly where
   the wrappers' `uint32_t` parameters are read from.
2. **libm calls the compiler generates itself.** `math.sin`, `math.cos`, and
   `clamp`/`min`/`max` on floats compile to calls to `sinf`, `cosf`, `fminf`,
   `fmaxf`, ... , which are hard-float. `lib/libm/bridge.c` defines `vito_sinf`,
   `vito_cosf`, ... (float bits in and out through integer registers), and
   `build.bat` renames the symbols **inside the Odin object only** with
   `objcopy --redefine-syms=lib\libm\redefine.syms`. vita2d and newlib keep
   calling the real functions. To cover another libm function add it to
   `lib/libm/bridge.c` and `lib/libm/redefine.syms`.

To check what an Odin object calls:

```
arm-vita-eabi-nm -u build\<name>.odin.o
```

Anything that looks like a libm name (`sinf`, `powf`, `fmodf`, ...) without a
`vito_` prefix is a bug waiting to happen. The vita2d example logs a self-test at
startup (`selftest sin(1)*1e6=841470 cos(1)*1e6=540302 max(2x,-3x)=2`) to prove
the libm bridge works.

## Writing bindings

Look at the real headers before writing a struct or constant:

```
C:\vitasdk\arm-vita-eabi\include\psp2\          (e.g. ctrl.h, display.h, gxm.h)
C:\vitasdk\arm-vita-eabi\include\psp2common\    (shared structs and enums)
C:\vitasdk\arm-vita-eabi\include\vita2d.h
```

Do not write enum values from memory. A guessed `TextureFilter` enum had wrong
values until it was checked against `gxm.h`.

To find which stub library provides a function:

```
arm-vita-eabi-nm C:\vitasdk\arm-vita-eabi\lib\libSceAppMgr_stub.a | findstr sceSharedFbOpen
```

`lib/sce/sce.odin` has `#assert(size_of(...))` checks for the structs whose
sizes the headers pin down. Keep doing this for new structs.

The link line `vita2d` needs (in `Examples/Vita2D-Example/build.bat`):

```
-lvita2d -lSceDisplay_stub -lSceGxm_stub -lSceSysmodule_stub -lSceCtrl_stub
-lScePgf_stub -lScePvf_stub -lSceCommonDialog_stub -lSceAppMgr_stub
-lSceSysmem_stub -lSceLibKernel_stub -lfreetype -lpng16 -ljpeg -lz -lbz2 -lm
```

`-lSceAppMgr_stub` is easy to miss: `sceSharedFb*` and `sceAppMgrGetBudgetInfo`
live there.

---

## Debugging a crash on real hardware

A crashed app shows `An error has occurred in the following application.
(C2-12828-1)` and saves a core dump to `ux0:data/psp2core-*.psp2dmp`. Copy it to
the PC (VitaShell USB or FTP). The dump only matches the exact build that
produced it, so keep that build's `build\<name>.elf` and do not rebuild first.

Reading it with `vita-parse-core` (<https://github.com/xyzz/vita-parse-core>):

1. Clone it into its own folder and create a Python virtual environment there.
2. `pip install pyelftools==0.29`. The version pinned in its `requirements.txt`
   (0.24) does not import on Python 3.13, and 0.30+ may remove `py3compat`, which
   the script imports.
3. The script is Python 2 code. On Python 3 the helper functions in `util.py`
   that handle bytes and strings (`c_str`, `hexdump`, `u16`, `u32`) need small
   fixes, because indexing bytes gives ints.
4. Run it with `arm-vita-eabi-addr2line` and `arm-vita-eabi-objdump` on `PATH`:

```
python main.py <core>.psp2dmp <build>\<name>.elf
```

It prints the crashed thread's PC, LR, registers and disassembly around the PC.
Compare the PC against the load address: the first crash looked like it was in
`_init_vita_heap` at `0x8108d74c`, which is ELF address `0x4474c`, so the module
was loaded at `0x81049000`, not `0x81000000`. See gotcha 8.

---

## Gotchas

These all caused a real failure while setting this up.

1. **`build.bat` must have CRLF line endings.** With LF-only endings `cmd.exe`
   mis-parses the file (symptoms: `'tlocal' is not recognized as an internal or
   external command`, or commands from an unrelated script running). The repo's
   `.gitattributes` keeps `.bat` files CRLF.
2. **Run `build.bat` from PowerShell or cmd, not Git Bash.** `cmd //c build.bat`
   from Git Bash ran the wrong script.
3. **The linker rejects Odin's object file** with
   `uses VFP register arguments, <file>.o does not`. `build.bat` removes the
   `.ARM.attributes` section from the Odin objects (`arm-vita-eabi-objcopy
   --remove-section .ARM.attributes`) so the link goes through. This only
   silences the linker; see [The float ABI](#the-float-abi-read-this-before-binding-anything-with-floats)
   for the real problem.
4. **Do not put `::` comments inside a parenthesized batch block** (a `for`
   loop or `if (...)`). It is parsed as a label and fails with `The system
   cannot find the drive specified.` Use `REM` there.
5. **Do not free the framebuffer before exiting.** Freeing the display's CDRAM
   block while it is still scanning out closed the whole Vita3K emulator. Just
   call `sceKernelExitProcess(0)`.
6. **`@(no_bounds_check)` is not an Odin attribute**, and `^=` is not XOR-assign
   (`^` is the dereference operator, so `x ^= 1` fails with "Cannot dereference").
   Use `x ~= 1`. Indexing a multi-pointer (`[^]T`) is not bounds-checked anyway,
   and slicing one needs both bounds (`p[a:b]`).
7. **Do not draw into the buffer that is being displayed.** On real hardware the
   CPU fill of a 960x544 CDRAM buffer takes longer than a frame, so a shape drawn
   last was wiped before it was ever scanned out (the white square never
   appeared). Vita3K hides this. Use two buffers: draw into the hidden one, call
   `sceDisplaySetFrameBuf(..., .NEXTFRAME)`, then `sceDisplayWaitSetFrameBuf()`
   before reusing the other.
8. **Link with `-Wl,-q`.** Without it the ELF has no relocations, so
   `vita-elf-create` emits an empty `.sce.rel`. Vita3K always loads at
   `0x81000000` and does not care, but a real Vita loads the module at a
   different address, so the first absolute address (`movw`/`movt`) faults with
   a data abort before `main()` runs. That is how it showed up in the core dump.
   With `-q`, `readelf -SW` on the ELF shows `.rel.text`, `.rel.data`, ... and the
   `.sce.rel` section in the `.velf` grows (2.3 KB to 93 KB in the vita2d example).
9. **`vita2d_draw_pixel` is unreliable on real hardware.** It draws a GXM `POINTS`
   primitive and never sets a point size. Vita3K draws 1 px, but the real GPU drew
   a larger, flickering square. The binding's `DrawPixel` draws a 1x1 rectangle
   instead; the raw version is `DrawPoint`.
10. **Make the GPU idle before freeing anything it can use.** The last frame is
    still queued when the loop exits. Freeing a texture or font at that point
    froze the app, and later hung the GPU and the whole console. At shutdown call
    `vita2d.WaitRenderingDone()`, then free textures and fonts, then exit.
11. **`vita2d_fini` hangs Vita3K v0.2.1.** The log stops right at the call and
    nothing is printed inside it; the real Vita runs it fine. With the GPU idle
    (gotcha 10), the example skips it and calls `sceKernelExitProcess`, and that
    exits cleanly on both the emulator and the hardware. A `CALL_FINI` constant
    in `Examples/Vita2D-Example/main.odin` turns it back on.
12. **Check the Odin object for stray libm calls** (see the float ABI section).
    A `sinf` without the `vito_` prefix links and runs without any error and
    returns wrong values.

---

## Not verified

- **64-bit arguments.** On ARM32, `u64` arguments must start in an even-numbered
  register. The O3DX (3DS) project found Odin's `freestanding_arm32` does not
  insert that padding. Not yet checked for the Vita; no function bound so far
  takes a `u64`. Bind such functions through a `bridge.c` wrapper and test them on hardware.
- **Double-precision (`f64`) libm wrappers.** `lib/libm/bridge.c` also defines
  the `double` versions (`vito_sin`, ...), but only the `float` versions have
  been exercised.
- **Vita2D functions beyond the example.** The example uses `Init`,
  `StartDrawing`/`EndDrawing`/`SwapBuffers`, `ClearScreen`, `SetClearColor`,
  `DrawFillCircle`, `DrawLine`, `DrawRectangle`, `DrawPixel`, `DrawTexture`,
  `DrawTextureScale`, `DrawTextureScaleRotate`, `DrawTextureTintScale`,
  `LoadPNGBuffer`, `TextureSetFilters`, `LoadDefaultPvf`, `PvfDrawText`,
  `WaitRenderingDone`, `FreeTexture` and `FreePvf`. The other bound functions
  compile but have not been run: the remaining texture and font loaders,
  `DrawTexturePart*`, `DrawTextureRotate*`, `DrawTextureTint*`, clipping,
  `PvfTextWidth`/`PvfTextHeight`, `DrawPoint`, `Fini` (hangs Vita3K).
- **CPU target.** The Odin object is tagged `ARM1176JZF-S` (ARMv6), not
  Cortex-A9. It runs on the hardware, but Odin's `-microarch` option has not been tried.
- **Touch beyond what the example uses.** `sceTouchPeek`, `sceTouchSetSamplingState`
  and `sceTouchGetPanelInfo` are confirmed on hardware (front and back panels).
  `sceTouchRead`, `sceTouchGetSamplingState`, `sceTouchEnableTouchForce` /
  `DisableTouchForce`, the `force` value and the `HIDE_UPPER_LAYER` flag are bound
  but not exercised. The touch example has not been run in Vita3K, and how that
  emulator handles the back panel is unknown. The region and "Ext" `SceTouch`
  functions are not bound.
- **Libraries beyond `SceCtrl`, `SceDisplay`, `SceSysmem`, `SceLibKernel`, `SceTouch`
  and `vita2d`.** No audio, networking, file I/O, motion sensors or 3D (`SceGxm`)
  bindings yet.
