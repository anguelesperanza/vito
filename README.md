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
  vito/               Odin runtime and helpers: allocators, logger, assertions, print, input layer, frame timer, audio mixer, WAV loader, dialogs, system events
  vita2d/             libvita2d bindings + bridge.c (float wrappers); text.odin draws sharp text at any size
  gfx/                SceGxm without vita2d: setup, shaders, textures, render targets; 2D sprites, shapes and text
  net/                networking: sockets, DNS, HTTP (the console's own HTTPS is too old for current servers)
  vorbis/             Ogg Vorbis music streamed through the mixer (stb_vorbis)
  video/              MP4 playback through the console's hardware decoder
  libm/               bridge.c + redefine.syms: makes math.sin/cos/min/max work (hard-float libm)
tools/bindgen/
  gen.py              the binding generator (Python 3 + pycparser)
  linkcheck.py        links every bound function against the stub libraries
  report.md           what was generated, and what was left out and why
tools/make_livearea.py   placeholder LiveArea icon and pictures for a project (sce_sys)
tools/make_test_sounds.py   synthesises the WAV files Mixer-Example plays
tools/gen_libm_syms.py   regenerates lib/libm/redefine.syms
tools/make_font.py       bakes a TrueType font into the atlas lib/gfx draws text from
tools/make_test_media.py makes Media-Example's Ogg and MP4 files with ffmpeg
tools/net_test_server.py PC side of Net-Example: TCP / UDP echo server
tools/gxp_info.py        prints a compiled shader's header and parameters
tools/build_shaders.py   compiles Cg shaders to .gxp (needs your own tools/psp2cgc.exe, which is git-ignored)
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
  System-Example/       lib/vito dialogs and on-screen keyboard, power and resume events, system modules
  Gxm-Example/          SceGxm with our own shaders: triangle, texture, blending, depth, lighting, render to texture
  Sprite-Example/       lib/gfx 2D: batched sprites, shapes, baked-font text, PNG loading, over a 3D scene
  GxmFeatures-Example/  stencil, mipmaps, texture formats, lines and points, instancing, region clip
  Net-Example/          lib/net: connection info, DNS, HTTP and HTTPS, TCP and UDP with a PC
  Media-Example/        Ogg music streaming, MP4 video, camera
docs/                 setup guide, roadmap, notes on the .gxp shader format
```

AI may be used to generate these bindings to speed up the time it takes to development and to solve issues / bugs along the way
