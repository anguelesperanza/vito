# Vito -- A WIP / POC Playstation Vita development bindings for Odin

Vito, if it pans out, is meant to become a part of Matchbox as the third target platform form it (PC and 3DS being the other two).

This repo would serve as a way to host the stand along bindings / code that Matchbox will use for it.

`build.bat` turns Odin source into a `.vpk`. The raw-framebuffer demo, the vita2d demo (sprites, shapes, text)
and the audio demo run in Vita3K and on a real (hacked) PS Vita; the touch demo has been run on the hardware.

**Bindings:** `lib/sce` covers the whole user-mode VitaSDK (`psp2/*.h`): 123 files, 1,649 functions, generated from
the installed headers by `tools/bindgen/gen.py`, with every struct layout and constant checked against GCC and every
function link-checked against the stub libraries. Only the functions the examples call have actually run on a console;
the rest compile and link but are untested. `lib/vita2d` binds libvita2d by hand.

See [docs/getting-started.md](docs/getting-started.md) for setup, how the build works, the float ABI problem, and the
gotchas that were hit on real hardware, and [docs/roadmap.md](docs/roadmap.md) for what is left.

```
lib/
  bridge_utils.h      u2f / f2u helpers for float ABI bridge .c files
  sce/                generated bindings, one file per SDK header (ctrl.odin, gxm.odin, net_net.odin, ...)
    sce.odin          naming rules and ABI notes (hand-written)
    inline.odin       ports of the headers' static inline functions and macros (hand-written)
    helpers.odin      small extras: Color32, thread defaults, ... (hand-written)
    bridge.c          generated float wrappers for the 21 SCE functions that pass floats by value
  vito/               Odin runtime and helpers: allocators, logger, assertions, print, input layer, frame timer, audio mixer, WAV loader
  vita2d/             libvita2d bindings + bridge.c (float wrappers); text.odin draws sharp text at any size
  libm/               bridge.c + redefine.syms: makes math.sin/cos/min/max work (hard-float libm)
tools/bindgen/
  gen.py              the binding generator (Python 3 + pycparser)
  linkcheck.py        links every bound function against the stub libraries
  report.md           what was generated, and what was left out and why
tools/make_livearea.py   placeholder LiveArea icon and pictures for a project (sce_sys)
tools/make_test_sounds.py   synthesises the WAV files Mixer-Example plays
tools/gen_libm_syms.py   regenerates lib/libm/redefine.syms
NewProjectTemplate/   main.odin, main.c, build.bat -> MyGame.vpk (framebuffer demo)
Examples/
  Vita2D-Example/       vita2d demo
  Vita2D-Full-Example/  every vita2d function, eight pages
  Touch-Example/        front + back touch demo
  Audio-Example/        4-key synthesizer (audio thread)
  Platform-Example/     clock, file I/O, input edges
  Runtime-Example/      lib/vito: allocator, fmt, maps, log, threads, atomics, assertions
  SaveData-Example/     save file, SceAppUtil slots and system parameters, power, assets and LiveArea
  Input-Example/        lib/vito input layer: buttons, sticks, both touch panels, motion
  Sync-Example/         kernel mutex, semaphore, event flag, cond, rwlock, message pipe, thread info, frame timer
  Mixer-Example/        lib/vito audio mixer and WAV loader, BGM and VOICE ports, microphone
docs/                 setup guide, roadmap
```

AI may be used to generate these bindings to speed up the time it takes to development and to solve issues / bugs along the way
