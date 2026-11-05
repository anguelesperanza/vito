# Getting started

How to build a PS Vita `.vpk` from Odin source on Windows with `build.bat`.

Only steps that were run and worked are listed here. Anything not yet tested is
under [Not verified](#not-verified).

**Tested with:** Windows 11, Odin `dev-2026-11:e28f5d1ff`, VitaSDK `2026.08`
(`arm-vita-eabi-gcc` 15.2.0), Vita3K v0.2.1.

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

## 2. Build the template project

From **PowerShell or cmd** (not Git Bash, see [Gotchas](#gotchas)):

```
cd NewProjectTemplate
.\build.bat
```

Output: `MyGame.vpk` in the same folder.

Edit the settings at the top of `build.bat` for your own project:

| Variable   | Meaning                                              |
|------------|------------------------------------------------------|
| `TARGET`   | Output name (`<TARGET>.vpk`)                         |
| `TITLE_ID` | Exactly 9 characters: 4 letters then 5 digits        |
| `TITLE`    | Name shown under the bubble                          |

## 3. Run it

**Vita3K:** use *File → Install .vpk*, pick `MyGame.vpk`, then start "My Game".

The template fills the screen with a scrolling gradient and a white square.

| Input              | Effect                                           |
|--------------------|--------------------------------------------------|
| D-pad / left stick | Move the square                                  |
| Cross              | Swap the gradient colours (also logs a line)     |
| Start              | Exit                                             |

The app also logs `odin_main: started` through `sceClibPrintf`, which shows in
Vita3K's log window.

---

## How the pipeline works

```
main.odin
   │  odin build . -target:freestanding_arm32 -build-mode:asm -no-entry-point
   ▼                -min-link-libs -no-thread-local -o:speed
ARM assembly (.S)
   │  arm-vita-eabi-gcc -c  -march=armv7-a -mtune=cortex-a9 -mfpu=neon -mfloat-abi=hard
   ▼
Odin object (.o)  ── arm-vita-eabi-objcopy --remove-section .ARM.attributes
   │
   │   + main.c object (C entry point -> odin_main)
   ▼
arm-vita-eabi-gcc  -lSceCtrl_stub -lSceDisplay_stub -lSceSysmem_stub -lSceLibKernel_stub
   ▼
ELF  ── vita-elf-create ─► velf ── vita-make-fself -c ─► eboot.bin
                                   vita-mksfoex ───────► param.sfo
                                                          │
                  vita-pack-vpk -s param.sfo -b eboot.bin ▼
                                                      MyGame.vpk
```

- `main.c` defines `main()` and calls the Odin procedure exported with
  `@(export, link_name = "odin_main")`.
- Odin does not know the SCE libraries. Bindings use `foreign import
  "system:SceCtrl_stub"` and similar, which the linker resolves against
  VitaSDK's stub libraries. The Vita resolves the real functions at load time.

## Writing bindings

Look at the real headers before writing a struct or constant:

```
C:\vitasdk\arm-vita-eabi\include\psp2\          (e.g. ctrl.h, display.h)
C:\vitasdk\arm-vita-eabi\include\psp2common\    (shared structs and enums)
```

To find which stub library provides a function:

```
arm-vita-eabi-nm C:\vitasdk\arm-vita-eabi\lib\libSceSysmem_stub.a | findstr sceKernelAllocMemBlock
```

`lib/sce/sce.odin` has `#assert(size_of(...))` checks for the structs whose
sizes the headers pin down. Keep doing this for new structs.

---

## Gotchas

These all caused a real failure while setting this up.

1. **`build.bat` must have CRLF line endings.** With LF-only endings `cmd.exe`
   mis-parses the file (symptoms: `'tlocal' is not recognized as an internal or
   external command`, or commands from an unrelated script running).
2. **Run `build.bat` from PowerShell or cmd, not Git Bash.** `cmd //c build.bat`
   from Git Bash ran the wrong script.
3. **The linker rejects Odin's object file** with
   `uses VFP register arguments, <file>.o does not`. Odin's object is not
   marked hard-float, VitaSDK's are. `build.bat` removes the `.ARM.attributes`
   section from the Odin objects (`arm-vita-eabi-objcopy --remove-section
   .ARM.attributes`) so the link goes through.
4. **Do not put `::` comments inside a parenthesized batch block** (a `for`
   loop or `if (...)`). It is parsed as a label and fails with `The system
   cannot find the drive specified.` Use `REM` there.
5. **Do not call `sceKernelFreeMemBlock` on the framebuffer before exiting.**
   Freeing it while the display is still scanning it out closed the whole
   Vita3K emulator when Start was pressed. Just call `sceKernelExitProcess(0)`;
   the kernel releases the block.
6. **`@(no_bounds_check)` is not an Odin attribute.** Indexing a multi-pointer
   (`[^]T`) is not bounds-checked anyway.
7. **Slicing a multi-pointer needs both bounds** (`p[a:b]`). `p[a:]` is invalid.

---

## Not verified

- **Real hardware.** Everything above was run in Vita3K only.
- **Float arguments.** Odin emits soft-float code and VitaSDK is hard-float.
  Stripping the ABI attributes only lets the linker accept the mix. Calls that
  take or return `f32`/`f64` (for example in `vita2d`) will probably need
  C wrapper functions that take the float bits as `uint32_t`; `lib/bridge_utils.h`
  has the `u2f`/`f2u` helpers for this. Not yet tried.
- **64-bit arguments.** On ARM32, `u64` arguments must start in an even-numbered
  register. The O3DX (3DS) project found Odin's `freestanding_arm32` does not
  insert that padding. Not yet checked for the Vita; no function bound so far
  takes a `u64`.
- **CPU target.** The Odin object is tagged `ARM1176JZF-S` (ARMv6), not
  Cortex-A9. It runs, but Odin's `-microarch` option has not been tried.
- **Libraries beyond `SceCtrl`, `SceDisplay`, `SceSysmem` and `SceLibKernel`.**
