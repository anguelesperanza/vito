# Roadmap

What exists, what has been proven on a real PS Vita, and what is left, in the order
it should be done. The end goal is a set of Odin bindings and a small runtime that
Matchbox can use as its third target (PC and 3DS are the others), built with
`build.bat`.

Status legend:

- ✅ done and run on real hardware
- 🟡 partly done (the text says which part)
- ⬜ not started

Last updated 2026-11-12. Toolchain: Odin `dev-2026-11:e28f5d1ff`, VitaSDK `2026.08`
(`arm-vita-eabi-gcc` 15.2.0).

---

## Where things stand

| Phase | What | Status | Short version |
|---|---|---|---|
| 0 | Build pipeline and proof of concept | ✅ | Odin to `.vpk` works, on hardware |
| | SDK bindings (`lib/sce`) | 🟡 | everything the headers declare is bound and links; a small part has run |
| | `vita2d` bindings | ✅ | all 100 non-variadic functions; sharp text helper added |
| 1 | Odin runtime (`lib/vito`) | ✅ | allocator, logger, assertions; two small items open |
| 2 | Kernel, threads and time | 🟡 | bound; threads, clock and atomics run; sync objects not exercised |
| 3 | Files, save data and packaging | ✅ | save survives a restart; three details unrecorded |
| 4 | Complete input | ⬜ | bound; needs the example and an input layer. **Next** |
| 5 | 2D graphics on `SceGxm` | ⬜ | `vita2d` covers 2D for now |
| 6 | Complete audio | 🟡 | output works; mixer and decoding not started |
| 7 | The rest of `SceGxm` (3D, shaders) | ⬜ | bound, never called |
| 8 | System UI and services | ⬜ | bound, never called (except `SceAppUtil`, `ScePower`) |
| 9 | Networking | ⬜ | bound, never called |
| 10 | Media and codecs | ⬜ | bound, never called |

"Bound" below always means: generated from the header, layout checked against GCC,
and link-checked against the stub library. It does **not** mean the call has been
made on a console.

### What is in the repository

| Path | What it is |
|---|---|
| `lib/sce/` | Generated bindings for the whole user-mode SDK: 123 files, 1,649 functions, 350 structs. Hand-written: `sce.odin` (naming and ABI notes), `inline.odin` (30 `static inline` functions and the useful macros, ported), `helpers.odin` |
| `lib/sce/bridge.c` | Generated float wrappers for the 21 SCE functions that pass a float by value (`gxm`, `motion`, `pgf`, `pvf`) |
| `lib/vito/` | The Odin runtime: heap allocator, temp allocator, logger, print helpers, assertion handler |
| `lib/vita2d/` | Hand-written `libvita2d` bindings, the float bridge, and `text.odin` (`DrawText`: sharp text at any size) |
| `lib/libm/` | Wrappers for libm and for libgcc's float conversion helpers, plus `redefine.syms` (308 names) |
| `tools/bindgen/gen.py` | The binding generator (Python 3, `pycparser`). `report.md` lists what it produced and skipped |
| `tools/bindgen/linkcheck.py` | Links every bound function against the stub libraries and runs the ABI checks |
| `tools/gen_libm_syms.py` | Regenerates `lib/libm/redefine.syms` |
| `tools/make_livearea.py` | Placeholder LiveArea icon and pictures for a project |
| `NewProjectTemplate/` | Framebuffer demo on `lib/vito`, with `sce_sys` LiveArea files |

### Examples and what each has proven

| Example | Title ID | Covers | On a real Vita |
|---|---|---|---|
| `NewProjectTemplate` | `ODIN00001` | raw framebuffer, `SceCtrl`, `SceDisplay`, memory blocks | ✅ (before it moved to `lib/vito`; not re-run since) |
| `Vita2D-Example` | `ODIN00002` | sprites, shapes, text | ✅ |
| `Touch-Example` | `ODIN00003` | front and back touch panels | ✅ |
| `Audio-Example` | `ODIN00004` | `SceAudioOut` from a thread | ✅ |
| `Vita2D-Full-Example` | `ODIN00005` | every `vita2d` function, eight pages | ✅ |
| `Platform-Example` | `ODIN00006` | process clock, file I/O, input edges | ✅ |
| `Runtime-Example` | `ODIN00007` | `lib/vito`, `core:fmt`/`log`/`strings`/`strconv`/`slice`/`linalg`, a second thread, atomics, a failing assertion | ✅ all 12 checks, and the panic log |
| `SaveData-Example` | `ODIN00008` | save file, `SceAppUtil`, `ScePower`, assets and LiveArea from the VPK | ✅ restart test |

Two caveats on that column:

- After the last hardware runs of the first six, every `build.bat` gained the
  `__sce_headroom` link flag and the generic asset packaging step. Both change the
  layout or contents of the `.vpk`, not the code, but those six have not been re-run
  since. `SaveData-Example` was built and run with both.
- **Vita3K has not been used since the bindings were regenerated.** Nothing in this
  table says anything about the emulator.

### What "all of the SDK is bound" leaves out

1. **Most bound functions have never been called.** The examples use roughly a
   hundred of the 1,649. Each later phase is mostly about moving one area from
   "links" to "runs".
2. **Functions VitaSDK has a stub for but no prototype.** The user-mode stub libraries
   export 6,817 names; the headers declare 1,649 of them, and those are what is bound.
   The other 5,168 have no C declaration anywhere in VitaSDK, so there is nothing to
   generate from. 62 libraries have no header at all (`SceLibc` 1,074 names, `SceFios2`,
   `SceLibXml`, `SceLibJson`, `SceAvcodec`, `SceNpTrophy` and the other `SceNp*`,
   `SceUlt`, `SceSas`, `SceVoice`, `SceRudp`, ...), and many bound libraries are partial
   (`SceTouch` 7 of 27, `SceGxm` 225 of 288, `SceAppMgr` 46 of 331; a lot of the
   remainder are internal `_sce*` syscall variants). Binding any of these needs
   signatures from another source (Sony SDK documentation or reverse engineering), by
   hand, in a non-generated file.
3. **Left out on purpose:** `psp2/paf*` (system applications only), `psp2kern` (kernel
   mode, see "Out of scope"), and two debug macros.

---

## Findings that shape the work

These came out of the work so far. Each one cost time to find, and each still applies.

1. **Odin's float calling convention does not match VitaSDK's.** Odin passes `f32` /
   `f64` in integer registers; VitaSDK expects VFP registers. A mismatched call links,
   runs and returns garbage. It shows up in three places, all handled:
   - SDK and library functions with float parameters: C wrappers (`lib/sce/bridge.c`,
     generated; `lib/vita2d/bridge.c`, by hand).
   - libm calls the compiler emits (`sinf`, `fmaf`, ...): `lib/libm/bridge.c`.
   - libgcc helpers for float to 64-bit integer conversion (`__fixdfdi`,
     `__floatundidf`, ...), which `core:fmt` and `core:strconv` use: also
     `lib/libm/bridge.c`. This one was found late, while building the runtime.

   `redefine.syms` now renames **every** libm function inside the Odin object, so a
   call with no wrapper fails at link time by name instead of misbehaving silently.
2. **64-bit arguments are fine.** O3DX found an older Odin did not put `u64` arguments
   in even register pairs. Odin `dev-2026-11` does (checked in the generated assembly,
   together with small structs by value, struct returns, narrow integers and C
   variadics). `sceIoLseek`, `sceRtc*` and the other 64-bit calls are bound directly.
   One 64-bit path has run on hardware (`sceKernelGetProcessTimeWide` returns a `u64`);
   a `u64` *argument* has not been exercised on a console yet.
3. **VitaSDK uses short enums.** `sizeof` of most SDK enums is 1, not 4, which changes
   struct layouts. The earlier hand-written bindings assumed 4. The generator takes
   every size from GCC; every Odin enum is 32-bit and enum-typed struct fields are
   narrowed where GCC stores them narrow.
4. **Build for the Cortex-A9.** `-microarch:cortex-a9` replaces the ARMv6 default.
   Atomics then use `dmb ish` / `ldrex` / `strex` instead of a deprecated CP15 barrier,
   and they work: two threads on one atomic counter pass on hardware. The separate
   `lib/atomic` C bridge that was planned is no longer needed.
5. **Odin on this target has no allocator and silent assertions.** Solved by
   `lib/vito`. Still true and not solvable from our side: bounds-check and nil
   failures trap with no message, because the Odin runtime does not route them
   through a hook.
6. **`vita-elf-create` overflows when the code ends just below a 64 KiB boundary.** It
   appends its metadata to the code segment without checking the space. Every
   `build.bat` links with `-Wl,--defsym,__sce_headroom=0x10000`, the linker script's
   own hook for this. This was the "random" packaging crash.
7. **`vita2d` scales one glyph bitmap for every text size.** Below scale 1.0 that drops
   pixels and squeezes letters. `v2d.DrawText` rasterises the system font at each size
   instead (confirmed on hardware). The PGF text functions have the same weakness and
   no helper yet.
8. **Real hardware finds bugs the emulator hides.** Missing relocations, a single
   display buffer, an audio buffer reused while playing, freeing GPU memory in use,
   and the text problem above all appeared only on a Vita. Every phase ends with an
   example on hardware.
9. **An Odin compiler bug to avoid:** comparing a `cstring` with `""` can abort the
   compiler on this target ("missing procedure 'cstring_to_string'"). Test the first
   byte instead.

The details and the remaining gotchas are in [getting-started.md](getting-started.md).

---

## Phase 0: build pipeline and proof of concept ✅

`build.bat`: Odin to ARM assembly to GCC to `.vpk`, with relocations, float bridges,
libm symbol renaming, the Cortex-A9 target, SCE headroom, and packing of `assets\`
and `sce_sys\`. Run on hardware many times.

## SDK bindings (`lib/sce`) 🟡

Done:

- Generated from VitaSDK 2026.08: 123 files (one per header, `psp2/*.h` merged with
  the matching `psp2common/*.h`), 1,649 functions across 84 stub libraries.
- Every struct size (350) and field offset (1,818) equals what GCC reports.
- Every function links against the stub library the binding names.
- 21 float functions go through the generated bridge.
- 30 `static inline` functions and the useful function-like macros are ported by hand.

Open:

- Hardware coverage, area by area, in the phases below.
- The 5,168 exported functions with no prototype (see above). Only worth doing one
  library at a time, when a game needs it.
- An SCE error-name table (`0x80xxxxxx` to a name) for readable logs. The generator
  already knows every error constant, so it can write this file.

## Phase 1: Odin runtime (`lib/vito`) ✅

Done and confirmed on hardware with `Runtime-Example` (12 of 12 checks):

- Heap allocator on newlib `malloc` (128 MiB heap by default, changeable with
  `_newlib_heap_size_user` in `main.c`), including aligned and large allocations.
- Temp allocator (a growing arena), freed once per frame.
- `vito.init()`, `vito.thread_context()`, `vito.shutdown()`; `init` also runs Odin's
  global initialisers, which nothing else does under `-no-entry-point`.
- `vito.print` / `println` / `printf` and a `context.logger`, so `core:log` works.
- Assertion handler: message and location to the log and to
  `ux0:data/vito_panic.log`, then a trap (crash screen and core dump).
- `core:fmt`, `log`, `strings`, `strconv`, `slice`, `math` and `math/linalg` build and
  run on this target.

Open:

- **Main-thread stack size.** How a VitaSDK app sets it was not found in this
  toolchain. Thread stacks created with `sceKernelCreateThread` are set by the caller
  and are not affected.
- The SCE error-name table (listed under the bindings).
- Not tried in Vita3K.

## Phase 2: kernel, threads and time 🟡

Bound: all of `threadmgr` (threads, mutex, lightweight mutex and condition, semaphore,
event flag, condition variable, message pipe, rwlock, callbacks), `processmgr`,
`sysmem`, `modulemgr`, `rtc`, `clib`, the `sceKernelAtomic*` functions, fibers.

Run on hardware: thread create / start / wait / delete / exit, `sceKernelDelayThread`,
`sceKernelGetProcessTimeWide`, memory blocks (alloc, base, free),
`sceRtcGetCurrentClockLocalTime`, `sceClibPrintf` / `sceClibSnprintf`, and Odin
atomics from two threads.

Open:

- An example that uses a mutex, a semaphore and an event flag between two threads.
  None of the sync objects has been called.
- `sceKernelPowerTick` (stops auto-suspend), thread priority and CPU affinity, timers.
- A frame-time helper in Odin (delta time from the process clock); the example
  computes it by hand today.

Done when: a threaded example uses a mutex, a semaphore and an event flag, and a
frame-time helper, on hardware.

## Phase 3: files, save data and packaging ✅

Done and confirmed on hardware:

- File I/O (`Platform-Example`): open, read, write, `lseek32`, stat, mkdir, remove,
  directory listing, reading from `app0:/`.
- `SaveData-Example`: a save file that survives closing and restarting the app.
- `build.bat` packs `assets\` (readable as `app0:/assets/...`) and `sce_sys\`.
- `tools/make_livearea.py` writes LiveArea images in the required sizes and format.

Not recorded from the hardware run (the example shows each on screen):

- Whether the save went to `savedata0:` or to the `ux0:data/<title id>/` fallback,
  that is, whether a homebrew VPK can use the app's own save area.
- Whether the `SceAppUtil` save-data slot calls succeeded.
- Whether the bubble shows the custom icon and LiveArea pictures.

Open:

- Power callbacks and suspend / resume (bound, not exercised). Moved to Phase 8.
- `sceIoLseek` with a 64-bit offset (bound, not called; `sceIoLseek32` is what ran).

## Phase 4: complete input ⬜ (M) — next

Everything is bound; nothing beyond basic polling has run.

- `SceCtrl` rest: `PeekBufferPositive2` / `ReadBuffer*`, negative logic, external
  controller ports (DualShock 4 via `GetControllerPortInfo`), button intercept and
  lock. The handheld's shoulder buttons are `LTRIGGER` / `RTRIGGER`, not `L1` / `R1`.
- `SceTouch` rest: force, `sceTouchRead`, sampling state. Only 7 of the library's 27
  functions have prototypes, so the region and "Ext" calls cannot be bound from the
  SDK.
- `SceMotion`: accelerometer and gyro state, sampling, tilt correction. Three calls
  pass a float and are the first use of `lib/sce/bridge.c` on hardware.
- `SceHid` (USB / Bluetooth keyboard and mouse) and `SceCamera`: try them, mark them
  untested if there is nothing to test with.
- An Odin input layer: pressed / released / held edges, stick dead zones, and
  touch-to-screen mapping (the `Touch-Example` helpers, generalised). This is what
  Matchbox will want instead of raw polling.

Done when: one `Input-Example` shows buttons, both sticks, both touch panels and
motion live, on hardware.

## Phase 5: 2D graphics on a slice of `SceGxm` ⬜ (L)

`vita2d` carries 2D today, and that is enough for Matchbox's first integration.
Replacing it with direct `SceGxm` is still open (decision 2). Matchbox is moving to
"everything is 3D, including 2D", which makes it likely this phase merges into
Phase 7 rather than being built separately.

If it is built on its own, the slice is: setup (`sceGxmInitialize`, context, render
target, display queue, shader patcher), precompiled shaders, vertex and index buffers,
blend state, textures, then in Odin a triangle batch, a textured and tinted sprite,
bitmap text and a sprite-sheet layer. The float functions are already bridged. Do not
free GPU memory until the GPU is done with it.

Capstone, here or in Phase 7: port O3DX's `FlappyClone` (sprites, animation, physics,
audio, saves). It exercises Phases 1 to 4 and 6 together.

## Phase 6: complete audio 🟡 (L)

Run on hardware: a `MAIN` mono port at 48 kHz, double-buffered output from a thread,
volume, the drain call.

Open:

- `SceAudioOut` rest: stereo, the `BGM` and `VOICE` ports, other sample rates,
  `SetConfig` / `GetConfig`, `SetAlcMode`.
- `SceAudioIn` (microphone).
- An Odin mixer: channels with volume, pan and looping, driven from the audio thread.
- Decoding: see "Audio decoding notes". Not decided.

Done when: an example plays looping music and overlapping effects from files in the
VPK with volume control, and records from the microphone, on hardware.

## Phase 7: the rest of `SceGxm` (3D and custom shaders) ⬜ (XL)

225 `SceGxm` functions are bound, four through the float bridge. None has been called
directly (`vita2d` calls them internally).

1. Depth and stencil, culling, render targets, render to texture, multisampling,
   texture formats, mipmaps, the remaining state.
2. **Shader toolchain.** See "Shader notes"; this is the first real blocker, because
   `SceGxm` only runs precompiled `.gxp` programs.
3. Math: `core:math/linalg` works on this target (confirmed in `Runtime-Example`), so
   no separate math file is needed. Matrix multiply goes through the libm bridge
   (`fmaf`), which is correct but not fast; measure before optimising.
4. Examples, as in O3DX: triangle, texture, depth test, alpha blend, spinning cube,
   then lighting written as shaders (the Vita has no fixed-function pipeline).

Done when: the spinning-cube and a lit-scene example run on hardware.

## Phase 8: system UI and services ⬜ (M)

All bound. `SceAppUtil` system parameters and `ScePower` readings are already used by
`SaveData-Example`. Do the rest as needed, roughly in this order:

- `SceSysmodule`: load optional system modules.
- Common dialogs: message dialog, IME (text input) dialog and `libime`, netcheck,
  photo import and review. The `*ParamInit` helpers are ported in `inline.odin`.
- Power callbacks and suspend / resume, `notificationutil`, `screenshot`, `shellutil`,
  `appmgr` (app parameters, launching other apps), `registrymgr`.
- `sqlite`, and the export helpers (`photoexport`, `musicexport`, `videoexport`).

Done when: a `System-Example` opens a message dialog and a text-input dialog and
survives suspend and resume, on hardware.

## Phase 9: networking ⬜ (L)

All bound: `SceNet` (sockets, resolver, epoll), `SceNetCtl`, `SceHttp`, `SceSsl`, ad hoc.

Done when: examples do an HTTP GET, a UDP send and receive, and print connection info,
on hardware. Ad hoc needs two consoles; mark it untested if there is only one.

## Phase 10: media and codecs ⬜ (L, optional)

All bound: `avplayer`, `videodec`, `jpeg` / `jpegenc`, `audiodec` / `audioenc`, `atrac`,
`mp4rec`, camera, USB audio and serial. Only if a game needs them.

## Out of scope

The kernel-mode headers (`psp2kern`, and kernel-only `psp2common` functions) are for
taiHEN plugins and `.skprx` modules, a different target with different stubs and a
different build. A plugin target could be added later but is not part of this plan.

## Definition of done

For the generated `sce` bindings, the first two points are automatic: run `gen.py`,
then `linkcheck.py`.

1. Layouts, values and signatures come from the headers and GCC, never from memory.
   Hand-written bindings (`vita2d`, anything from a non-SDK library) need an
   `#assert(size_of(...))` per struct with the size taken from the compiler.
2. ABI: a float passed by value goes through a `bridge.c`; the Odin object has no `mcr`
   instruction; an unwrapped libm call now fails at link time by itself.
3. An example that exercises it, run **on hardware**, and in Vita3K where that works.
4. An entry in `docs/getting-started.md` saying exactly what was confirmed and what
   was not.
5. This file and the README updated.

## Tooling

Exists: `tools/bindgen/gen.py`, `tools/bindgen/linkcheck.py`, `tools/gen_libm_syms.py`,
`tools/make_livearea.py`.

Still wanted:

- A crash-dump helper that wraps the patched `vita-parse-core` steps from
  [getting-started.md](getting-started.md). More useful now that bounds-check failures
  are known to trap without a message.
- A `new-example` script: copy the template with a fresh title ID and LiveArea files.
- The error-name table from the generator.

No longer needed: `tools\check-abi.bat` (the link now fails on its own for an
unwrapped float call, and `linkcheck.py` runs the remaining checks) and the separate
size-assert audit (the generator checks every size and offset).

## Decisions

### Decided

1. **Raw SCE bindings, few dependencies, no SDL / vitaGL / OpenAL.** (Owner, from
   Matchbox's `full-rewrite` branch.) `vita2d` is used first because it ships
   precompiled shaders. It pulls in freetype, libpng, libjpeg, zlib and bzip2, which
   is the opposite of "few dependencies", so a later move to `SceGxm` directly stays
   on the table (open decision 2).
2. **The SDK bindings are generated, not hand-written.** One flat `sce` package, one
   file per header, regenerated when VitaSDK is updated. Non-SDK libraries get their
   own hand-written package, as `vita2d` has.
3. **Naming:** drop `Sce` / `SCE_` and nothing else; an enum becomes an Odin enum only
   when a function or struct takes that type; flags and error codes are untyped
   constants. The rules are in `lib/sce/sce.odin`.
4. **Soft-float Odin with C bridges, for now.** Odin already has hard-float argument
   lowering for arm32 but emits a target triple that makes LLVM fall back to
   soft-float (found in Matchbox's render plan, 2026-11-12). A fixed compiler would
   remove every bridge and the libm renaming on both the 3DS and the Vita. That is
   Matchbox's "Phase I"; nothing here depends on it.

### Open

1. **Shader strategy** for `SceGxm`. See "Shader notes". Blocks Phases 5 and 7.
2. **Whether 2D moves from `vita2d` to `SceGxm`**, and if so whether as its own phase
   or as part of 3D.
3. **Audio decoding.** See "Audio decoding notes".
4. **How Matchbox tells the 3DS and the Vita apart**, since both are
   `freestanding arm32`. Left to the project owner.

## Shader notes

"Offline" means compiling the shader on the development PC at build time and
shipping the compiled `.gxp` binary. "Runtime" means shipping source and compiling
it on the console each run (or once, then caching). `SceGxm` only runs `.gxp`.

| Route | Runs where | Needs | Pros | Cons |
|---|---|---|---|---|
| Ship precompiled `.gxp` blobs, checked into the repo | nothing at run time | the compiler once, by whoever edits a shader | no compiler on the console; works in Vita3K (the vita2d demo already does this); simplest to ship | a shader change needs one of the routes below |
| Sony `psp2cgc.exe` (from Sony's SDK host tools) | PC, in `build.bat` | a copy of Sony's SDK file | the standard offline route, output matches what commercial games use | proprietary and cannot be redistributed; not installed here; not confirmed to run natively on Windows |
| `SceShaccCg` / `vitaShaRK` at run time | the Vita | `libshacccg.suprx` on every console (`ur0:data/`), plus `SceShaccCgExt` for vitaShaRK | shader source can change without a PC tool; `SceShaccCg` is bound (7 of its 33 functions have prototypes) | the module is not in firmware; every user must install it; LGPL on vitaShaRK; Vita3K support unknown; a hitch on first compile |
| `psp2spvc` (open source, SPIR-V to GXP) | PC | a SPIR-V producer such as `glslang` or `dxc` | no Sony file; Matchbox PC already has HLSL | described as experimental and years old; not tried |

None of these has been run. Suggested path: **ship precompiled blobs for the few
Matchbox shaders**, produce them once, and revisit the compiler question only for
Matchbox's "custom shading language" item, which its own roadmap marks as uncertain.

## Audio decoding notes

Matchbox already converts at build time: `tools/mp3towav` (Odin plus
`vendor:miniaudio`, runs on the PC) turns MP3 / FLAC / OGG into 16-bit WAV, and the
3DS loads WAV from `romfs`. The Vita can do the same from `app0:/assets/`.

| Option | What it is | Pros | Cons |
|---|---|---|---|
| A. Convert on the PC, load WAV | reuse `mp3towav`; write a small WAV reader in Odin | no decoder on the console; no dependencies; same as 3DS | big files (48 kHz stereo is about 11 MB per minute); fine for effects, heavy for long music |
| B. Vita hardware decoders | `SceAudiodec` (MP3, AAC, AT9, CELP), `SceAtrac` (ATRAC9 files); both bound | no CPU cost; no code to ship | you parse the container yourself for `SceAudiodec`; ATRAC9 needs Sony's encoder; aligned buffers and a large control struct; no Ogg; Vita3K behaviour unknown |
| C. Single-file C decoder built by `build.bat` | e.g. `stb_vorbis.c` (in the Odin install under `vendor/stb/src`), compiled like `main.c` | vendored source, not an install; Ogg compresses well; float code stays inside C, so no bridge | CPU cost on the Cortex-A9 not measured; a C file in the repo |
| D. `vdpm` libraries | `libvorbis`+`libogg`, `libtremor`, `opusfile`, `libmad`, `flac`, `libopenmpt`, `libxmp` | proven | each is a separate install and link; Odin bindings would be extra surface for no gain over C |

Suggested: **A for effects, C (`stb_vorbis`) for music**, and B later only if CPU
time turns out to matter. Skip D.

Images follow the same logic. `vita2d` loads PNG, JPEG and BMP from files or memory
today (it links libpng and libjpeg). `core:image/png` does not compile for this
target as shipped (it imports `core:os`), so a `SceGxm` path without `vita2d` would
convert images at build time, as Matchbox does for the 3DS with `tritex`.

## Matchbox backend mapping

Matchbox's `full-rewrite` branch has one file per concern per target. A Vita backend
would fill the same files:

| Matchbox file | Needs | Vita today |
|---|---|---|
| `window_*` | init, cleanup, screen size | `vita2d.Init`, 960 x 544 constants ✅ |
| `events_*`, `input_*` | pressed / held / released, sticks | `SceCtrl` ✅; the edge logic is written per example until the Phase 4 input layer exists. Keyboard and mouse return false, as on the 3DS |
| `render_*` | start, clear, end, triangles | `StartDrawing`, `ClearScreen`, `EndDrawing` + `SwapBuffers` ✅; triangles through `DrawArray` with pool vertices (`vita2d` has no triangle call) |
| `sprite_*` | create from a file, draw with scale, rotation, tint, source rectangle | `LoadPNGFile("app0:/assets/...")` and the `DrawTexture*` family ✅ |
| `audio_*` | play sounds | `SceAudioOut` ✅ for raw PCM; loading and mixing are Phase 6 (Matchbox's 3DS audio is an empty stub today) |
| `logger_*`, `util_*` | print, delta time, allocation | `vito.print*` and `core:log` ✅, `sceKernelGetProcessTimeWide` ✅, `lib/vito` allocators ✅ |
| assets | files in the package | `assets\` packed by `build.bat` ✅ |

The two blockers the earlier version of this file listed for integration are gone:
there is an allocator, and assets are packed. What remains before a Vita backend can
be written:

1. **Target selection.** Matchbox picks backends with `#+build freestanding arm32` and
   a `_3ds_freestanding_arm32` file suffix; a Vita backend matches the same tags.
   It needs a `-define` constant or another mechanism (open decision 4).
2. **Matchbox's move to 3D rendering for everything.** If the PC and 3DS backends go
   that way first, the Vita backend should target `SceGxm` (Phase 7) rather than be
   written against `vita2d` and rewritten.

## Suggested path

| Milestone | Phases | What Matchbox gets | State |
|---|---|---|---|
| A: 2D game target | 1, 2, 3, 4, 6, and 2D through `vita2d` | sprites, text, input, audio, saves, assets | 1 and 3 done; 2 and 6 partly; 4 next |
| B: 3D | 7 (and 5 if kept separate) | depth, render targets, custom shaders | blocked on the shader decision |
| C: online and system features | 8, 9 | dialogs, power events, networking | not started |
| D: extras | 10, 12 | video, polish, the demo game | not started |

Shortest route to something playable: Phase 4 (input layer and example), then the
audio mixer and WAV loading from Phase 6, then a first Matchbox backend on `vita2d`.
The shader decision can be made in parallel, since nothing in milestone A depends
on it.
