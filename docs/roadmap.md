# Roadmap

What exists, what has been proven on a real PS Vita, and what is left, in the order
it should be done. The end goal is a set of Odin bindings and a small runtime that
Matchbox can use as its third target (PC and 3DS are the others), built with
`build.bat`.

Status legend:

- ✅ done and run on real hardware
- 🟡 partly done (the text says which part)
- ⬜ not started
- ➡️ folded into another phase

Last updated 2026-11-13. Toolchain: Odin `dev-2026-11:e28f5d1ff`, VitaSDK `2026.08`
(`arm-vita-eabi-gcc` 15.2.0).

---

## Where things stand

**Every phase is done.** A game written in Odin can draw 2D and 3D with its own
shaders, read every input the console has, play effects, compressed music and video,
save, show system dialogs and use the network, and all of that has run on a real
Vita. What remains is listed under "What is left" just below the tables: a short list
of things to revisit, areas of the SDK nobody has needed yet, and checks that were
skipped.

| Phase | What | Status | Short version |
|---|---|---|---|
| 0 | Build pipeline and proof of concept | ✅ | Odin to `.vpk` works, on hardware |
| | SDK bindings (`lib/sce`) | 🟡 | everything the headers declare is bound and links; 274 of the 1,649 functions are called by the examples and helper packages, the rest have never run |
| | `vita2d` bindings | ✅ | all 100 non-variadic functions; sharp text helper added |
| 1 | Odin runtime (`lib/vito`) | ✅ | allocator, logger, assertions; two small items open |
| 2 | Kernel, threads and time | ✅ | threads, sync objects, timing and the frame timer run on hardware; callbacks and fibers untried |
| 3 | Files, save data and packaging | ✅ | save survives a restart; three details unrecorded |
| 4 | Complete input | ✅ | input layer and `Input-Example` run on hardware; DualShock-only calls, HID and camera untried |
| 5 | 2D graphics on `SceGxm` | ➡️ | folded into Phase 7; `vita2d` covers 2D |
| 6 | Complete audio | ✅ | mixer, WAV loader, `BGM` / `VOICE` ports and microphone run on hardware; compressed music and streaming were added in Phase 10 |
| 7 | `SceGxm` (3D, shaders, and the 2D slice) | ✅ | shaders, `lib/gfx` and `Gxm-Example` (3D, textures, lighting, render to texture) and the 2D layer (`Sprite-Example`) and `GxmFeatures-Example` (stencil, mipmaps, texture formats, lines, points, instancing) run on hardware; 60 fps up to about 2,400 sprites; region clip only works as "keep inside" |
| 8 | System UI and services | ✅ | dialogs, keyboard, power and resume events, notification, PS button lock run on hardware; `libime`, photo dialogs, `sqlite`, exports untried |
| 9 | Networking | ✅ | sockets, DNS and HTTP run on hardware; HTTPS to modern servers needs a bundled TLS library (owner decision) |
| 10 | Media and codecs | ✅ | Ogg music streaming, MP4 video and the camera run on hardware; hardware audio decoders, JPEG and encoders untried |

"Bound" below always means: generated from the header, layout checked against GCC,
and link-checked against the stub library. It does **not** mean the call has been
made on a console.

### What is in the repository

| Path | What it is |
|---|---|
| `lib/sce/` | Generated bindings for the whole user-mode SDK: 123 files, 1,649 functions, 350 structs. Hand-written: `sce.odin` (naming and ABI notes), `inline.odin` (30 `static inline` functions and the useful macros, ported), `helpers.odin` |
| `lib/sce/bridge.c` | Generated float wrappers for the 21 SCE functions that pass a float by value (`gxm`, `motion`, `pgf`, `pvf`) |
| `lib/vito/` | The Odin runtime (heap and temp allocators, logger, print helpers, assertion handler) and the helpers every game uses: input layer, frame timer, file reading, audio mixer with WAV loading and streams, system dialogs and on-screen keyboard, power and resume events |
| `lib/gfx/` | `SceGxm` without `vita2d`: setup, shader programs, textures of any format, render targets; a 2D layer (sprite batch, shapes, PNG loading, baked-font text). Its own shaders are in `lib/gfx/shaders` |
| `lib/net/` | Networking: start-up, connection info, DNS, TCP and UDP sockets, HTTP |
| `lib/vorbis/` | Ogg Vorbis music streamed through the mixer; the decoder is the vendored `stb_vorbis.c` |
| `lib/video/` | MP4 playback through `SceAvPlayer`, drawn by `lib/gfx` |
| `lib/vita2d/` | Hand-written `libvita2d` bindings, the float bridge, and `text.odin` (`DrawText`: sharp text at any size) |
| `lib/libm/` | Wrappers for libm and for libgcc's float conversion helpers, plus `redefine.syms` (308 names) |
| `tools/bindgen/gen.py` | The binding generator (Python 3, `pycparser`). `report.md` lists what it produced and skipped |
| `tools/bindgen/linkcheck.py` | Links every bound function against the stub libraries and runs the ABI checks |
| `tools/gen_libm_syms.py` | Regenerates `lib/libm/redefine.syms` |
| `tools/make_livearea.py` | Placeholder LiveArea icon and pictures for a project |
| `tools/build_shaders.py` | Compiles Cg shaders to `.gxp` with the owner's `tools/psp2cgc.exe` (git-ignored); `tools/gxp_info.py` prints a compiled shader's header and parameters |
| `tools/make_font.py` | Bakes a TrueType font into the atlas `lib/gfx` draws text from |
| `tools/make_test_sounds.py`, `tools/make_test_media.py` | Synthesise the WAV, Ogg and MP4 files the examples play |
| `tools/net_test_server.py` | The PC side of `Net-Example` |
| `docs/gxp-format.md` | What is known about the compiled shader format |
| `NewProjectTemplate/` | A starting point for a game on `lib/vito` and `lib/gfx`: sprite, text, input, sound, packed assets, `sce_sys` LiveArea files |

### Examples and what each has proven

| Example | Title ID | Covers | On a real Vita |
|---|---|---|---|
| `NewProjectTemplate` | `ODIN00001` | a sprite, text, input and a sound on `lib/vito` and `lib/gfx` (rewritten 2026-11-13) | ✅ |
| `Framebuffer-Example` | `ODIN00018` | raw framebuffer, `SceCtrl`, `SceDisplay`, memory blocks; the template's previous contents | ✅ |
| `Vita2D-Example` | `ODIN00002` | sprites, shapes, text | ✅ |
| `Touch-Example` | `ODIN00003` | front and back touch panels | ✅ |
| `Audio-Example` | `ODIN00004` | `SceAudioOut` from a thread | ✅ |
| `Vita2D-Full-Example` | `ODIN00005` | every `vita2d` function, eight pages | ✅ |
| `Platform-Example` | `ODIN00006` | process clock, file I/O, input edges | ✅ |
| `Runtime-Example` | `ODIN00007` | `lib/vito`, `core:fmt`/`log`/`strings`/`strconv`/`slice`/`linalg`, a second thread, atomics, a failing assertion | ✅ all 12 checks, and the panic log |
| `SaveData-Example` | `ODIN00008` | save file, `SceAppUtil`, `ScePower`, assets and LiveArea from the VPK | ✅ restart test |
| `Input-Example` | `ODIN00009` | `lib/vito` input layer: buttons, sticks, both touch panels, motion; the `SceMotion` float bridge | ✅ |
| `Sync-Example` | `ODIN00010` | kernel sync objects between two threads, thread info, timing, the frame timer | ✅ all 13 checks |
| `Mixer-Example` | `ODIN00011` | `lib/vito` mixer and WAV loader, `BGM` and `VOICE` ports, microphone | ✅ |
| `System-Example` | `ODIN00012` | message, progress and error dialogs, the on-screen keyboard, power callback and resume events, `SceSysmodule`, notification, screenshot switch, PS button lock, launching Settings | ✅ |
| `Gxm-Example` | `ODIN00013` | `SceGxm` without `vita2d`, through `lib/gfx`: own shaders, triangle, texture filtering, alpha blending, depth test and culling, shader lighting, render to texture, 4x MSAA | ✅ |
| `Sprite-Example` | `ODIN00014` | 2D on `lib/gfx`: batched sprites (scale, rotation, flip, source rectangle, tint), shapes, additive blending, baked-font text, PNG through libpng, 2D into a render target, 2D over 3D | ✅ |
| `GxmFeatures-Example` | `ODIN00015` | stencil, mipmaps, swizzled / 16-bit / paletted / DXT1 textures, lines, points, wireframe, instancing, region clip | ✅ (region clip: only "keep inside" works, see Phase 7) |
| `Net-Example` | `ODIN00016` | `lib/net`: connection info, DNS, HTTP and HTTPS GET, TCP and UDP echo with a PC, TCP server, a worker thread | ✅ except HTTPS |
| `Media-Example` | `ODIN00017` | Ogg Vorbis music streamed through the mixer (`lib/vorbis`), MP4 video through `SceAvPlayer` (`lib/video`), the camera | ✅ |

Two caveats on that column:

- After the last hardware runs of the first six, every `build.bat` gained the
  `__sce_headroom` link flag and the generic asset packaging step. Both change the
  layout or contents of the `.vpk`, not the code, but those six have not been re-run
  since. `SaveData-Example` was built and run with both.
- **Vita3K has not been used since the bindings were regenerated.** Nothing in this
  table says anything about the emulator.

### What is left

Nothing here blocks making a game. In rough order of how likely it is to matter:

1. **To revisit** (details in the section of that name):
   - HTTPS to current servers needs a TLS library shipped with the game; deferred.
   - `sceGxmSetRegionClip`: `.INSIDE` behaves like `.OUTSIDE` on hardware.
2. **Never checked:**
   - Vita3K, since the bindings were regenerated. Every result in this file is from a
     real console.
   - The first six examples, since `build.bat` gained the headroom flag and asset
     packaging. The rebuilt `Mixer-Example` and `Runtime-Example`, since the mixer
     gained streams.
   - Which of `video.mp4` and `video_b.mp4` plays (at least one does), and whether
     video colours and sound sync are right.
   - Three `SaveData-Example` details: where the save landed (`savedata0:` or the
     fallback), the slot line, and the bubble icon.
   - What region clip's `.ALL` mode does; which of `.CW` and `.CCW` culls outward
     faces.
3. **Bound but never called, by area:** callbacks other than power, fibers; DualShock
   calls, HID; `libime`, photo dialogs, `registrymgr`, `sqlite`, the export helpers;
   the netcheck dialog, `epoll`, ad hoc networking; `SceAudiodec`, `SceAtrac`,
   `SceJpeg`, the encoders, raw `videodec`, USB audio and serial; cube maps, PVRTC,
   `GXT` files, precomputed draw state.
4. **Small tooling wishes:** see "Tooling".
5. **Known limits that are not ours to fix:** bounds-check and nil failures trap with
   no message; the PGF text functions scale one bitmap, as `vita2d`'s PVF text did
   before `v2d.DrawText`.

### What "all of the SDK is bound" leaves out

1. **Most bound functions have never been called.** The examples and helper packages
   call 274 of the 1,649. Each phase moved one area from "links" to "runs"; the areas
   still at "links" are in the list above.
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
   Both directions have run on hardware: `sceKernelGetProcessTimeWide` returns a
   `u64`, and `sceHttpCreateRequestWithURL`, `sceIoPread` and `sceIoLseek` take 64-bit
   arguments (`Net-Example`, `lib/video`).
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

10. **`SceGxm` follows OpenGL's conventions closely enough to reuse its maths.** Clip
    space is -1 to 1 on every axis with +y up, and `core:math/linalg`'s projection
    matrices work as they are. Odin's matrix memory goes to a shader unchanged if the
    shader writes `mul(vector, matrix)`. Confirmed on hardware.
11. **System libraries fail silently when a callback does not do exactly what they
    ask.** `SceAvPlayer` wants picture memory aligned to 1 MiB; given 256 KiB it
    started and then stopped with no error. Its handle is an address, which reads as a
    negative `i32`, so the usual "negative means error" test rejects a good one. When a
    library misbehaves without an error code, put counters in the callbacks first:
    that is what found both.
12. **The console's own TLS is too old for current HTTPS servers.** The handshake
    fails before any certificate is checked. Plain HTTP and sockets are fine.
13. **Odin's `core:os` does not compile for this target,** which rules out
    `core:image/png` and anything else that imports it. PNG goes through VitaSDK's
    libpng instead; C code with floats (libpng, `stb_vorbis`) is no problem as long as
    no float crosses into Odin.

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

## Phase 2: kernel, threads and time ✅

Bound: all of `threadmgr` (threads, mutex, lightweight mutex and condition, semaphore,
event flag, condition variable, message pipe, rwlock, callbacks), `processmgr`,
`sysmem`, `modulemgr`, `rtc`, `clib`, the `sceKernelAtomic*` functions, fibers.

Run on hardware: thread create / start / wait / delete / exit, `sceKernelDelayThread`,
`sceKernelGetProcessTimeWide`, memory blocks (alloc, base, free),
`sceRtcGetCurrentClockLocalTime`, `sceClibPrintf` / `sceClibSnprintf`, and Odin
atomics from two threads.

Done and confirmed on hardware (all 13 checks pass):

- `Examples/Sync-Example` (`ODIN00010`): mutex and try-lock, lightweight mutex,
  semaphore and a wait timeout, event flag, condition variable, read/write lock,
  message pipe, `sceKernelGetThreadInfo`, priority change, CPU affinity,
  `sceKernelPowerTick`, `sceKernelAtomicAddAndGet32`. Each sync object is used between
  two threads, and every wait has a timeout so a failure shows as FAIL, not a freeze.
- `lib/vito/time.odin`: `Frame_Timer` / `frame_tick` (delta time, fps, clamped long
  frames), `time_us`, `sleep_ms`.

Open:

- Lightweight condition variables, callbacks, the `*CB` wait variants, fibers and the
  `Open*` / `Close*` calls for named objects: bound, not called.
- The message pipe works with the arguments from the SDK header's notes (type 0x40,
  attr 12, 4 KiB buffer); the header calls them uncertain, but they are what ran.

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

## Phase 4: complete input ✅ (M)

Done and confirmed on hardware (buttons, sticks, both touch panels, motion, and the
float bridge round trip):

- **The input layer, `lib/vito/input.odin`.** One `vito.input_update(&input)` per frame
  gives held / pressed / released buttons, both sticks as -1..1 with a round dead
  zone, front and back touches in screen pixels with a stable id and a "pressed this
  frame" flag, the ids of lifted fingers, and motion (acceleration, gyro, orientation
  quaternion). `BUTTON_L` / `BUTTON_R` match both the handheld's triggers and a
  DualShock's L1 / R1.
- **`Examples/Input-Example`** shows all of it live, and also calls directly:
  `sceCtrlGetSamplingMode`, `sceCtrlGetControllerPortInfo`, `sceTouchEnableTouchForce`,
  `sceTouchGetSamplingState`, `sceMotionGetTiltCorrection`, `sceMotionGetDeadband`, and
  the three float-bridged `SceMotion` calls as a set / read-back round trip. That
  round trip is the first use of the generated `lib/sce/bridge.c` on a console.

Not done:

- `sceCtrlPeekBufferPositive2` and the `Read*` / negative-logic variants, rapid fire,
  actuators (rumble) and the light bar: bound, not called. Most only matter with a
  DualShock on a PS TV.
- `SceHid` (USB / Bluetooth keyboard and mouse) and `SceCamera`: bound, not tried.
- `sceTouchRead` (the blocking read).

The original list for this phase, for reference:

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

## Phase 5: 2D graphics on a slice of `SceGxm` (folded into Phase 7)

Not a separate phase (decision 6). `vita2d` carries 2D, and Matchbox is moving to
"everything is 3D, including 2D", so the direct `SceGxm` work is done once, in
Phase 7. The 2D slice is kept here as a checklist for that phase.

The slice is: setup (`sceGxmInitialize`, context, render
target, display queue, shader patcher), precompiled shaders, vertex and index buffers,
blend state, textures, then in Odin a triangle batch, a textured and tinted sprite,
bitmap text and a sprite-sheet layer. The float functions are already bridged. Do not
free GPU memory until the GPU is done with it.

Capstone, here or in Phase 7: port O3DX's `FlappyClone` (sprites, animation, physics,
audio, saves). It exercises Phases 1 to 4 and 6 together.

## Phase 6: complete audio ✅ (L)

Run on hardware (`Audio-Example` and `Mixer-Example`): a `MAIN` mono port at 48 kHz,
double-buffered output from a thread, volume, the drain call, and everything below.

- **The mixer, `lib/vito/audio.odin`.** One stereo 48 kHz `MAIN` port fed by its own
  thread; 16 voices; per-voice volume, pan, pitch, looping and pause; a master volume
  and a peak meter. Sounds are mono or stereo at any sample rate and are resampled
  while mixing (linear interpolation, integer maths). Voice handles go stale safely.
- **A WAV loader** (`load_wav`, `load_wav_from_memory`): uncompressed PCM, 8 or 16 bit.
  Plus `read_entire_file` / `write_entire_file` in `lib/vito/file.odin`.
- **`Examples/Mixer-Example`** (`ODIN00011`): overlapping effects and a music loop from
  three WAV files in the VPK (8-bit mono 11 kHz, 16-bit mono 22 kHz, 16-bit stereo
  16 kHz, made by `tools/make_test_sounds.py`); a port test for the `BGM` port at
  44.1 kHz stereo and the `VOICE` port at 16 kHz mono with `SetConfig`, `GetConfig`,
  per-channel `SetVolume`, `GetRestSample`, `SetAlcMode` and `GetAdopt`; and one
  second recorded from the microphone (`SceAudioIn`) and played back.

Both items left open here were closed in Phase 10: compressed music is `lib/vorbis`,
and streaming is `vito.play_stream`.

Done when: an example plays looping music and overlapping effects from files in the
VPK with volume control, and records from the microphone, on hardware.

## Phase 7: `SceGxm` (3D, custom shaders, and the 2D slice) ✅ (XL)

225 `SceGxm` functions are bound, four through the float bridge.

Run on hardware (`Gxm-Example`):

- **Shader toolchain.** `tools/psp2cgc.exe` runs on this machine.
  `tools/build_shaders.py` compiles every `*_v.cg` / `*_f.cg` to `.gxp`; the `.gxp`
  files are checked in and embedded with `#load`.
- **`lib/gfx`**, a thin setup layer: `init` (context, ring buffers, three display
  buffers with the display queue, depth and stencil, shader patcher, optional 4x
  MSAA), `begin_frame` / `end_frame` / `swap`, `clear`, GPU memory (`alloc`, `free`),
  program registration and vertex / fragment program creation with blend modes,
  uniform helpers, linear textures, offscreen render targets, and
  `common_dialog_update`. Drawing itself is done with the `sce.sceGxm*` calls.
- **`Examples/Gxm-Example`** (`ODIN00013`), five pages: a triangle; a texture with
  point and linear filtering plus alpha blending; two cubes with the depth test and
  culling switchable; a textured cube lit by a shader; render to texture.

The rest of the phase:

- Culling works on hardware (owner, 2026-11-13: "looks good"). Which of `.CW` and
  `.CCW` removes the outward faces of the example's cubes was not written down; the
  example lets you switch and see. The matrix convention (`mul(vector, matrix)` with
  Odin's memory layout) and the OpenGL-style clip space are confirmed.
- **Sprite throughput, measured on hardware with `Sprite-Example`** (4x MSAA, a 3D
  cube behind, each sprite a 32 x 32 rotated, tinted, alpha-blended quad from one
  texture): 60 fps up to about 2,400 sprites, falling to about 35 fps at 4,000, the
  example's maximum. Where the time goes has not been measured. The likely cost is
  on the CPU, since every rotated sprite calls `sin` and `cos` through the libm
  bridge and writes four vertices; unrotated sprites and fewer overdrawn pixels
  would both move the number. Worth profiling before a game that needs more.
- Done and run on hardware, `Examples/GxmFeatures-Example` (`ODIN00015`): stencil (with a colour-masked fragment program), mipmaps on a swizzled
  texture, 16-bit, paletted and DXT1 textures, line and point primitives with width
  and per-vertex size, wireframe, instancing with a second vertex stream, and region
  clip. `lib/gfx` gained `create_texture_format`, `swizzle`,
  `create_vertex_program_streams` and `create_fragment_program_blend` for it.
  The swizzle bit order, the mip chain layout, the 565 and DXT1 layouts and the
  instanced draw's counts are all confirmed by that run.
- **Region clip finding.** On hardware `.OUTSIDE` and `.INSIDE` both keep only what
  is inside the rectangle, so "draw everywhere except this rectangle" is not
  available through `sceGxmSetRegionClip` as called here. The example now also
  cycles through `.ALL`, whose behaviour is not recorded yet. To cut a hole, use the
  stencil buffer.
- Not planned unless needed: `GXT` texture files, JPEG textures, cube maps, PVRTC,
  precomputed draw state, deferred contexts.
- Done and run on hardware, the 2D layer (the old Phase 5 slice):
  `lib/gfx/draw2d.odin` (sprite batch with `draw_texture`, `draw_texture_ex`,
  rectangles, lines, triangles, circles, blend modes), `lib/gfx/image.odin`
  (`load_png`, through VitaSDK's libpng), `lib/gfx/text.odin` (`load_font`,
  `draw_text`, `measure_text`) with `tools/make_font.py` baking a TrueType font into
  an atlas, and `Examples/Sprite-Example` (`ODIN00014`).
- Done: first notes on the `.gxp` format, in [gxp-format.md](gxp-format.md), with
  `tools/gxp_info.py` to print a file's header and parameters. They cover the
  container, not the instruction encoding.

The original list, for reference:

1. Depth and stencil, culling, render targets, render to texture, multisampling,
   texture formats, mipmaps, the remaining state.
2. **Shader toolchain.** `SceGxm` only runs precompiled `.gxp` programs. Decided:
   compile with `tools/psp2cgc.exe` and check the `.gxp` files in (see "Shader
   notes"). First step: confirm the compiler runs here and its output loads.
3. Math: `core:math/linalg` works on this target (confirmed in `Runtime-Example`), so
   no separate math file is needed. Matrix multiply goes through the libm bridge
   (`fmaf`), which is correct but not fast; measure before optimising.
4. Examples, as in O3DX: triangle, texture, depth test, alpha blend, spinning cube,
   then lighting written as shaders (the Vita has no fixed-function pipeline).

Done when: the spinning-cube and a lit-scene example run on hardware.

## Phase 8: system UI and services ✅ (M)

All bound. `SceAppUtil` system parameters and `ScePower` readings run on hardware
(`SaveData-Example`), and so does everything below (`System-Example`):

- **Dialogs, `lib/vito/dialog.odin`.** `dialog_init`; message boxes (OK, Yes / No,
  OK / Cancel, three custom buttons), the system error-code box, the system's
  ready-made messages, a progress bar; the on-screen keyboard (`text_input_open` /
  `text_input_poll`, with type, multiline and password options); `to_utf16` /
  `from_utf16`. One dialog at a time, opened and then polled each frame.
- **System events, `lib/vito/system.odin`.** A power callback on its own thread
  (`power_events_start`, `power_events_take`), `system_event_poll` (`SceAppMgr`
  resume events) and `system_ui_overlaid`.
- **`Examples/System-Example`** (`ODIN00012`): all of the above, plus direct calls to
  `SceSysmodule` (load and query), `sceNotificationUtilSendNotification`, the
  screenshot switch, the PS button lock (`SceShellSvc`), `sceAppMgrGetAppParam`,
  `sceAppUtilReceiveAppEvent` and launching Settings by URI.

Open:

- `libime` (a keyboard without the dialog frame), the netcheck dialog (with Phase 9),
  photo import and review dialogs, `registrymgr`.
- `sqlite`, and the export helpers (`photoexport`, `musicexport`, `videoexport`).

Done when: a `System-Example` opens a message dialog and a text-input dialog and
survives suspend and resume, on hardware.

## Phase 9: networking ✅ (L)

All bound: `SceNet` (sockets, resolver, epoll), `SceNetCtl`, `SceHttp`, `SceSsl`, ad hoc.

Run on hardware (`Net-Example`), everything except HTTPS: connection info, DNS, HTTP
GET (which also proves `u64` parameters), TCP and UDP echo with a PC, and the TCP
server on the console.

**HTTPS to modern servers does not work with the console's own TLS.** Measured on
hardware (2026-11-13) with `https://example.com/`, certificate check off:
`sceHttpSendRequest` returned `HTTP_ERROR_SSL` (0x80431075), the SSL error was
`HTTPS_ERROR_HANDSHAKE` (0x80435061), and the certificate callback was never
called. So the connection fails while agreeing on a TLS version and cipher, before
any certificate is looked at; the old CA list is a second problem behind that one,
not the cause. No `SceHttp` setting changes this.

- Whether `SceHttp`'s HTTPS works against a server that still accepts old TLS has
  not been tested, so the HTTPS path of `lib/net` is unproven either way.
- `sceHttpsDisableOption` with all five check flags returned 0x8043506B, an error
  the headers do not name. Unexplained; it did not matter here because the
  handshake failed first.
- **Decided (owner, 2026-11-13): not now.** HTTPS through a bundled TLS library is
  deferred until a game needs it; the plan for it is under "To revisit". Plain HTTP
  and raw sockets need nothing more.

- **`lib/net`**: `init` (loads the system modules, starts `SceNet`, `SceNetCtl`,
  `SceSsl` and `SceHttp`), connection info, `resolve` (DNS), TCP client and server,
  UDP, timeouts and non-blocking mode, `http_get` / `http_post` for HTTP and HTTPS,
  and a switch for the HTTPS certificate check.
- **`Examples/Net-Example`** (`ODIN00016`): connection info, a name lookup and HTTP
  GET, HTTPS with and without the certificate check, TCP and UDP echo against a PC,
  and a TCP server on the console. Network calls run on a worker thread.
- **`tools/net_test_server.py`**: the PC side (echo server, and a client for the
  console's server).

`sceHttpCreateRequestWithURL` takes a 64-bit argument, so the working HTTP GET is
also the first hardware confirmation of `u64` parameters.

Open: HTTPS through a bundled TLS library (see above); the netcheck dialog; `epoll`; ad hoc (needs two consoles;
untested); PSN (`np_*`), which is out of reach for homebrew.

Done when: examples do an HTTP GET, a UDP send and receive, and print connection info,
on hardware. Ad hoc needs two consoles; mark it untested if there is only one.

## Phase 10: media and codecs ✅ (L, optional)

All bound: `avplayer`, `videodec`, `jpeg` / `jpegenc`, `audiodec` / `audioenc`, `atrac`,
`mp4rec`, camera, USB audio and serial. Only if a game needs them.

All of it runs on hardware (`Media-Example`). Video took three fixes, each worth
remembering for other `Sce` libraries:

- A valid `SceAvPlayer` handle is an address and reads as a negative `i32`; only 0
  is a failure.
- The player is not "active" for a moment after a file is added, so "not active"
  must not be read as "finished" until it has been active once.
- **The player asks for its picture memory with 1 MiB alignment, and it must get
  it.** With 256 KiB alignment it opened the file, allocated, started, and then
  stopped without a picture or an error. `lib/video` now passes the alignment to
  `sceKernelAllocMemBlock`.

Not recorded from the run: whether both test encodings play (`video.mp4` is plain
ffmpeg output, `video_b.mp4` is closer to Sony's), whether colours are right, and
whether sound and picture are in step.

- **Streams in the mixer** (`lib/vito/audio.odin`): `play_stream` takes a callback
  that produces stereo audio on demand; two can play at once. This closes the
  "streaming" item left open in Phase 6.
- **Compressed music, `lib/vorbis`.** Ogg Vorbis decoded while it plays, with loop,
  pause, volume and seek. The decoder is `stb_vorbis` (public domain), vendored as
  `lib/vorbis/stb_vorbis.c` and compiled by `build.bat` through the `BRIDGES`
  mechanism. Its C side was tested on the PC against the example's file (all
  1,411,200 frames decoded); the Odin side and the stream path were not.
- **Video, `lib/video`.** MP4 (H.264 and AAC) through `SceAvPlayer`, the console's
  hardware decoder. Pictures are decoded into GPU memory and drawn as a YUV texture
  by `lib/gfx`; sound goes to the `BGM` port from a small thread.
- **Camera**, by direct `SceCamera` calls in the example: the picture is written
  straight into a texture.
- **`Examples/Media-Example`** (`ODIN00017`) and `tools/make_test_media.py`, which
  makes the Ogg and MP4 test files with ffmpeg.

Not done, and not planned unless a game needs it: the hardware audio decoders
(`SceAudiodec`, `SceAtrac`), which `stb_vorbis` makes unnecessary unless CPU time
becomes a problem; JPEG through `SceJpeg` (use PNG, or `vita2d`'s loader); encoders
(`jpegenc`, `audioenc`, `mp4rec`); raw `videodec`; USB audio and serial.

## To revisit

Things that work well enough to move on from, but that the owner wants looked at
again.

- **`sceGxmSetRegionClip` modes** (found 2026-11-13, `GxmFeatures-Example` page 6).
  On a real Vita `.OUTSIDE` and `.INSIDE` gave the same picture: only what is inside
  the rectangle is drawn. `.INSIDE` was expected to draw only outside it. The example
  passes the header's values unchanged, and the binding matches the header. Open
  questions for the revisit:
  - What `.ALL` does (the example cycles it now; not yet observed).
  - Whether the clipped edge follows the requested rectangle exactly or snaps to the
    GPU's 32-pixel tiles. The header calls this "tile clipping", and an inverted clip
    that only works on whole tiles could explain what was seen when the rectangle
    does not sit on tile boundaries. Try a rectangle aligned to multiples of 32.
  - Whether the mode has to be set before the first draw of a scene, or is latched
    per scene rather than per draw.
  - What Vita3K does with the same VPK.

  Until then: use `.OUTSIDE` to keep the inside, and the stencil buffer to cut a hole.

- **HTTPS to current servers** (deferred 2026-11-13; see Phase 9 for the measurements).
  The console's own TLS fails the handshake with a modern server
  (`HTTPS_ERROR_HANDSHAKE`, 0x80435061), so `lib/net`'s `http_get` only reaches
  `http://` URLs and servers that still accept old TLS. When a game needs HTTPS:
  1. Install the libraries with VitaSDK's package manager (`vdpm curl openssl`, which
     pulls in zlib; check the exact package names at the time). Neither is installed
     on the development machine today.
  2. Bind libcurl's "easy" interface by hand as its own package (`lib/curl`), the way
     `lib/vita2d` is done. `curl_easy_setopt` is variadic, so it needs small C
     wrappers per argument type in a `bridge.c`; none of the calls take floats.
  3. Give it a certificate bundle: the console's list is too old, so ship a current
     `cacert.pem` in the VPK and point curl at it (`CURLOPT_CAINFO`).
  4. Decide whether `net.http_get` should switch to curl or stay on `SceHttp` with a
     separate `curl` path. Sockets and DNS stay on `SceNet` either way, and curl on
     the Vita uses them underneath, so `net.init` is still needed.
  5. Expect a few megabytes more in the VPK, and check the libraries' licences
     (curl's is permissive; OpenSSL 3 is Apache 2.0) before shipping.

  Also unexplained from the same run, to look at then: `sceHttpsDisableOption` with
  all five check flags returned 0x8043506B; and whether `SceHttp`'s HTTPS works at
  all against a server that accepts old TLS was never tested.

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
`tools/make_livearea.py`, `tools/build_shaders.py`, `tools/gxp_info.py`,
`tools/make_font.py`, `tools/make_test_sounds.py`, `tools/make_test_media.py`,
`tools/net_test_server.py`.

Still wanted:

- A crash-dump helper that wraps the patched `vita-parse-core` steps from
  [getting-started.md](getting-started.md). More useful now that bounds-check failures
  are known to trap without a message.
- A `new-example` script: copy the template with a fresh title ID and LiveArea files.
- The error-name table from the generator (`net.http_error_name` covers a handful by
  hand).
- A sprite benchmark that separates CPU from GPU cost (see Phase 7).

No longer needed: `tools\check-abi.bat` (the link now fails on its own for an
unwrapped float call, and `linkcheck.py` runs the remaining checks) and the separate
size-assert audit (the generator checks every size and offset).

## Decisions

### Decided

1. **Raw SCE bindings, few dependencies, no SDL / vitaGL / OpenAL.** (Owner, from
   Matchbox's `full-rewrite` branch.) `vita2d` is used first because it ships
   precompiled shaders. It pulls in freetype, libpng, libjpeg, zlib and bzip2, which
   is the opposite of "few dependencies", so a later move to `SceGxm` directly stays
   on the table (see decision 6).
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

5. **Shaders ship as precompiled `.gxp` files.** (Owner, 2026-11-13.) They are compiled
   on the PC with Sony's `psp2cgc.exe`, which the owner has placed at
   `tools/psp2cgc.exe`. That file is proprietary: it is git-ignored and must never be
   committed, so the compiled `.gxp` files are checked in and a normal build does not
   need the compiler. See "Shader notes".
6. **2D on `SceGxm` is not its own phase.** (Owner, 2026-11-13.) `vita2d` covers 2D;
   the direct `SceGxm` work, 2D included, is done once, in Phase 7.
7. **No bundled TLS library for now.** (Owner, 2026-11-13.) The console's own HTTPS
   cannot reach current servers; adding libcurl and OpenSSL is deferred until a game
   needs it. The plan is under "To revisit".

### Open

1. **Audio decoding.** See "Audio decoding notes".
2. **How Matchbox tells the 3DS and the Vita apart**, since both are
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

**Decided (2026-11-13): the first route, with `psp2cgc.exe` as the tool that produces
the blobs.** Shader source and the compiled `.gxp` both live in the repo; the compiler
does not (`tools/psp2cgc.exe`, git-ignored). None of the routes has been run yet, and
whether `psp2cgc.exe` runs as-is on this machine is the first thing Phase 7 checks.

Considered and declined (owner, 2026-11-13): replacing `psp2cgc.exe` with a compiler
built from this repo. VitaSDK has no `psp2cgc.h`; its only shader-compiler header is
`psp2/shacccg.h` (already bound, `lib/sce/shacccg.odin`), which is the interface to
the compiler that runs on the console and needs Sony's `libshacccg.suprx` there. So
the only tool that could be built is a Vita app fed over the network, not a PC
executable. `psp2cgc.exe` stays.

What writing our own compiler would take (its four parts, why the instruction
encoder is the hard one, and a staged plan that starts from today's Cg route) is in
[gxp-format.md](gxp-format.md), under "What a compiler of our own would need".

Later, and outside vito's own scope: the owner plans a shader language for Matchbox
with a compiler that emits each target's shader format (PC, 3DS, Vita). For the Vita
that means writing `.gxp` directly, so the `.gxp` format will need to be documented
at some point. Phase 7 is a good place to collect notes, since it will have real
`psp2cgc` output to inspect, but that compiler is a Matchbox feature and not a
criterion for these bindings.

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
time turns out to matter. Skip D. **Done this way in Phase 10:** WAV for effects
(`vito.load_wav`), `lib/vorbis` for music.

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
| `events_*`, `input_*` | pressed / held / released, sticks | `SceCtrl` ✅; `lib/vito/input.odin` gives the edges and dead-zoned sticks ✅. Keyboard and mouse return false, as on the 3DS |
| `render_*` | start, clear, end, triangles | `StartDrawing`, `ClearScreen`, `EndDrawing` + `SwapBuffers` ✅; triangles through `DrawArray` with pool vertices (`vita2d` has no triangle call) |
| `sprite_*` | create from a file, draw with scale, rotation, tint, source rectangle | `LoadPNGFile("app0:/assets/...")` and the `DrawTexture*` family ✅ |
| `audio_*` | play sounds | `lib/vito/audio.odin` ✅: WAV loading and a 16-voice mixer on `SceAudioOut` (Matchbox's 3DS audio is an empty stub today) |
| `logger_*`, `util_*` | print, delta time, allocation | `vito.print*` and `core:log` ✅, `sceKernelGetProcessTimeWide` ✅, `lib/vito` allocators ✅ |
| assets | files in the package | `assets\` packed by `build.bat` ✅ |

The two blockers the earlier version of this file listed for integration are gone:
there is an allocator, and assets are packed. What remains before a Vita backend can
be written:

1. **Target selection.** Matchbox picks backends with `#+build freestanding arm32` and
   a `_3ds_freestanding_arm32` file suffix; a Vita backend matches the same tags.
   It needs a `-define` constant or another mechanism (open decision 2).
2. **Matchbox's move to 3D rendering for everything.** If the PC and 3DS backends go
   that way first, the Vita backend should target `SceGxm` (Phase 7) rather than be
   written against `vita2d` and rewritten.

## Suggested path

| Milestone | Phases | What Matchbox gets | State |
|---|---|---|---|
| A: 2D game target | 1, 2, 3, 4, 6, and 2D through `vita2d` | sprites, text, input, audio, saves, assets | done |
| B: 3D | 7 (includes 5) | depth, render targets, custom shaders | done |
| C: online and system features | 8, 9 | dialogs, power events, networking | 8 done; 9 done except HTTPS |
| D: extras | 10 | compressed music, video, camera | done |

All four milestones are reached. The bindings side has nothing left that a game
needs first; the next step is whatever the first real game turns up. 2D can go
through `vita2d` or through `lib/gfx`; a project that wants 3D, its own shaders or
video uses `lib/gfx` for everything, since the two cannot share a frame.
