# Vito -- A WIP / POC Playstation Vita development bindings for Odin

Vito, if it pans out, is meant to become a part of Matchbox as the third target platform form it (PC and 3DS being the other two).

This repo would serve as a way to host the stand along bindings / code that Matchbox will use for it.

POC / WIP. The template builds a `.vpk` with `build.bat` and runs in Vita3K (gradient + a square you move with the D-pad).
It has not been tried on real hardware yet, and anything involving float arguments is untested.

See [docs/getting-started.md](docs/getting-started.md) for setup, how the build works, and known gotchas.

```
lib/
  bridge_utils.h      u2f / f2u helpers for float ABI bridge .c files (not used yet)
  sce/sce.odin        bindings: SceCtrl, SceDisplay, SceSysmem, SceLibKernel (partial)
NewProjectTemplate/   main.odin, main.c, build.bat -> MyGame.vpk
docs/                 setup guide
```

AI may be used to generate these bindings to speed up the time it takes to development and to solve issues / bugs along the way
