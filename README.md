# Vito -- A WIP / POC Playstation Vita development bindings for Odin

Vito, if it pans out, is meant to become a part of Matchbox as the third target platform form it (PC and 3DS being the other two).

This repo would serve as a way to host the stand along bindings / code that Matchbox will use for it.

POC / WIP. `build.bat` turns Odin source into a `.vpk`, and both examples run in Vita3K and on a real (hacked) PS Vita:
a raw-framebuffer demo and a vita2d demo (sprites, shapes, text). Float arguments go through C bridge wrappers.
Only a small slice of the Vita API is bound so far.

See [docs/getting-started.md](docs/getting-started.md) for setup, how the build works, the float ABI problem, and the
gotchas that were hit on real hardware.

```
lib/
  bridge_utils.h      u2f / f2u helpers for float ABI bridge .c files
  sce/sce.odin        bindings: SceCtrl, SceDisplay, SceSysmem, SceLibKernel (partial)
  vita2d/             libvita2d bindings + bridge.c (float wrappers)
  libm/               bridge.c + redefine.syms: makes math.sin/cos/min/max work (hard-float libm)
NewProjectTemplate/   main.odin, main.c, build.bat -> MyGame.vpk (framebuffer demo)
Examples/
  Vita2D-Example/     vita2d demo -> Vita2D-Example.vpk
docs/                 setup guide
```

AI may be used to generate these bindings to speed up the time it takes to development and to solve issues / bugs along the way
