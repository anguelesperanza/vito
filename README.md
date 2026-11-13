# Vito -- A WIP / POC Playstation Vita development bindings for Odin

Vito, if it pans out, is meant to become a part of Matchbox as the third target platform form it (PC and 3DS being the other two).

This repo would serve as a way to host the stand along bindings / code that Matchbox will use for it.

## What it is

`build.bat` turns Odin source into a `.vpk` that installs and runs on a (hacked) PS Vita. Around that are:

- **`lib/sce`**: bindings for the whole user-mode VitaSDK (`psp2/*.h`): 123 files, 1,649 functions, generated from the
  installed headers by `tools/bindgen/gen.py`, with every struct layout and constant checked against GCC and every
  function link-checked against the stub libraries.
- **Helper packages** written on top of them, so a game does not start from raw system calls: `lib/vito` (runtime,
  input, timing, files, audio, dialogs), `lib/gfx` (2D and 3D drawing with your own shaders), `lib/net`, `lib/vorbis`
  (music) and `lib/video`. `lib/vita2d` binds libvita2d as an alternative for 2D.
- **Seventeen examples**, each of which has run on a real Vita, and a project template.

What has and has not been proven: the examples and helpers call 274 of the 1,649 bound functions, and those have run
on hardware. The rest compile and link but have never been called. Nothing has been checked in the Vita3K emulator
since the bindings were regenerated. HTTPS to current servers does not work with the console's own TLS.
[docs/roadmap.md](docs/roadmap.md) has the details and the list of what is left.

## Building

You need Odin, VitaSDK (default `C:\vitasdk`) and Python 3; [docs/getting-started.md](docs/getting-started.md) has
the setup. Then, from the template or any example folder:

```
cd NewProjectTemplate
.\build.bat
```

That writes `MyGame.vpk`; copy it to the Vita and install it with VitaShell. To start a project, copy
`NewProjectTemplate`, set `TARGET`, `TITLE_ID` and `TITLE` at the top of its `build.bat`, and fix the `..\lib` paths
(in `build.bat` and in the imports) if the copy lives somewhere else.

## A small example

This is the shape of [NewProjectTemplate/main.odin](NewProjectTemplate/main.odin): a sprite you move around, some
text, and a sound.

```odin
package my_game

import "core:fmt"
import gfx  "../lib/gfx"
import sce  "../lib/sce"
import vito "../lib/vito"

@(export, link_name = "odin_main")
game_main :: proc "c" (argc: i32, argv: [^]cstring) -> i32 {
    context = vito.init()            // heap, temp allocator, logger, assertions
    vito.input_init({})
    vito.audio_init()
    gfx.init()
    gfx.draw2d_init()

    // Files in the assets folder are packed into the .vpk and read from app0:/assets/
    png, _    := vito.read_entire_file("app0:/assets/player.png")
    player, _ := gfx.load_png(png)
    font, _   := gfx.load_font(#load("assets/font20.png"), #load("assets/font20.fnt"))
    blip, _   := vito.load_wav("app0:/assets/blip.wav")

    position := [2]f32{480, 272}
    input: vito.Input
    timer: vito.Frame_Timer

    for {
        dt := vito.frame_tick(&timer)                       // seconds since the last frame
        vito.input_update(&input)
        if vito.pressed(input, vito.BUTTON_START) do break

        position += (vito.dpad(input) + input.left_stick) * 300 * dt
        if vito.pressed(input, vito.BUTTON_CROSS) do vito.play_sound(blip)

        gfx.begin_frame()
        gfx.clear({0.08, 0.10, 0.18, 1})
        gfx.begin_2d()
        gfx.draw_texture(&player, position.x, position.y)
        gfx.draw_text(&font, 24, 36, fmt.tprintf("%.0f fps", timer.fps))
        gfx.end_2d()
        gfx.end_frame()
        gfx.swap()
        free_all(context.temp_allocator)
    }

    gfx.finish()
    sce.sceKernelExitProcess(0)
    return 0
}
```

The template itself checks every result and shuts everything down in order; this version leaves that out to fit on
a page. The other pieces work the same way:

| For | Use | Example |
|---|---|---|
| Buttons, sticks, touch, motion | `vito.input_update`, `vito.pressed` / `held` / `released` | `Input-Example` |
| Sound effects and music | `vito.play_sound`, `vorbis.play` | `Mixer-Example`, `Media-Example` |
| Sprites, shapes, text | `gfx.draw_texture_ex`, `gfx.draw_rect`, `gfx.draw_text` | `Sprite-Example` |
| 3D and your own shaders | `gfx.register_program`, the `sce.sceGxm*` calls | `Gxm-Example`, `GxmFeatures-Example` |
| Save files | `vito.read_entire_file` / `write_entire_file`, `SceAppUtil` | `SaveData-Example` |
| Message boxes, on-screen keyboard | `vito.message_dialog_open`, `vito.text_input_open` | `System-Example` |
| Sockets and HTTP | `net.tcp_connect`, `net.http_get` | `Net-Example` |
| Video, camera | `video.open`, `SceCamera` | `Media-Example` |
| Anything else | `lib/sce` directly | |

Text is drawn from a font atlas made on the PC:
`python tools\make_font.py C:\Windows\Fonts\DejaVuSans.ttf 20 assets\font20`.

## Shaders

2D drawing through `lib/gfx` needs no shaders of your own; its sprite and clear shaders are built in. You write
shaders when you draw 3D or want an effect.

The Vita's GPU only runs compiled shader programs (`.gxp` files), so a shader is written on the PC, compiled there,
and the compiled file is shipped. The compiled files are kept in the repository, which means **building a project
never needs the shader compiler; only changing a shader does.**

1. **Write the shader in Cg**, one file per program, named `NAME_v.cg` for a vertex program or `NAME_f.cg` for a
   fragment program:

   ```c
   // shaders/color_v.cg
   void main(
       float3 aPosition,
       float4 aColor,
       uniform float4x4 uMvp,
       out float4 vPosition : POSITION,
       out float4 vColor : COLOR0)
   {
       vPosition = mul(float4(aPosition, 1.f), uMvp);   // vector first: see below
       vColor = aColor;
   }
   ```

   ```c
   // shaders/color_f.cg
   float4 main(float4 vColor : COLOR0) : COLOR
   {
       return vColor;
   }
   ```

2. **Compile it.** The compiler is Sony's `psp2cgc.exe`. It is proprietary and is not in this repository: put your
   own copy at `tools\psp2cgc.exe` (git-ignored) or set the `PSP2CGC` environment variable to its path. Then:

   ```
   python tools\build_shaders.py MyGame\shaders
   ```

   That writes `color_v.gxp` and `color_f.gxp` next to the sources. Commit them.

3. **Use it.** Embed the compiled files and describe your vertex layout:

   ```odin
   Vertex :: struct { position: [3]f32, color: u32 }

   vertex_shader, _   := gfx.register_program(#load("shaders/color_v.gxp"))
   fragment_shader, _ := gfx.register_program(#load("shaders/color_f.gxp"))

   attributes := [?]sce.GxmVertexAttribute{
       gfx.attribute(vertex_shader, "aPosition", u16(offset_of(Vertex, position)), sce.GXM_ATTRIBUTE_FORMAT_F32, 3),
       gfx.attribute(vertex_shader, "aColor",    u16(offset_of(Vertex, color)),    sce.GXM_ATTRIBUTE_FORMAT_U8N, 4),
   }
   vertex_program   := gfx.create_vertex_program(vertex_shader, attributes[:], size_of(Vertex))
   fragment_program := gfx.create_fragment_program(fragment_shader, vertex_shader)
   mvp_param        := gfx.parameter(vertex_shader, "uMvp")

   // each frame, between gfx.begin_frame and gfx.end_frame:
   vertex_uniforms, _ := gfx.use_programs(vertex_program, fragment_program)
   gfx.set_uniform_matrix(vertex_uniforms, mvp_param, &mvp)
   sce.sceGxmSetVertexStream(gfx.ctx, 0, vertices)        // vertices and indices live in gfx.alloc memory
   sce.sceGxmDraw(gfx.ctx, .TRIANGLES, .U16, indices, index_count)
   ```

Three things to know before writing one:

- **Matrices:** pass Odin's matrix as it is and write `mul(vector, matrix)` in the shader, not `mul(matrix, vector)`.
  Clip space is the same as OpenGL's, so `core:math/linalg`'s projection matrices work unchanged.
- **Blending is part of the fragment program,** not a state you switch. For alpha blending make a second one:
  `gfx.create_fragment_program(fragment_shader, vertex_shader, .Alpha)`.
- **Unused inputs disappear.** The compiler removes any attribute or uniform the shader does not use, and
  `gfx.parameter` then returns nil for it. `python tools\gxp_info.py file.gxp` lists what a compiled shader has.

`Examples/Gxm-Example` is a complete worked example (colour, texture and lighting shaders), and the "3D and custom
shaders" section of [docs/getting-started.md](docs/getting-started.md) has the rest of the rules.
[docs/gxp-format.md](docs/gxp-format.md) describes what is known about the compiled format.

## What is where

```
lib/
  bridge_utils.h      u2f / f2u helpers for float ABI bridge .c files
  sce/                generated bindings, one file per SDK header (ctrl.odin, gxm.odin, net_net.odin, ...)
    sce.odin          naming rules and ABI notes (hand-written)
    inline.odin       ports of the headers' static inline functions and macros (hand-written)
    helpers.odin      small extras: Color32, thread defaults, ... (hand-written)
    bridge.c          generated float wrappers for the 21 SCE functions that pass floats by value
  vito/               Odin runtime and helpers: allocators, logger, assertions, print, input layer, frame timer, files,
                      audio mixer with WAV loading and streams, dialogs and on-screen keyboard, system events
  gfx/                SceGxm without vita2d: setup, shaders, textures, render targets; 2D sprites, shapes and text
  net/                networking: sockets, DNS, HTTP (the console's own HTTPS is too old for current servers)
  vorbis/             Ogg Vorbis music streamed through the mixer (stb_vorbis)
  video/              MP4 playback through the console's hardware decoder
  vita2d/             libvita2d bindings + bridge.c (float wrappers); text.odin draws sharp text at any size
  libm/               bridge.c + redefine.syms: makes math.sin/cos/min/max work (hard-float libm)
tools/
  bindgen/gen.py           the binding generator (Python 3 + pycparser)
  bindgen/linkcheck.py     links every bound function against the stub libraries
  bindgen/report.md        what was generated, and what was left out and why
  build_shaders.py         compiles Cg shaders to .gxp (needs your own tools/psp2cgc.exe, which is git-ignored)
  gxp_info.py              prints a compiled shader's header and parameters
  make_font.py             bakes a TrueType font into the atlas lib/gfx draws text from
  make_livearea.py         placeholder LiveArea icon and pictures for a project (sce_sys)
  make_test_sounds.py      synthesises the WAV files the examples play
  make_test_media.py       makes Media-Example's Ogg and MP4 files with ffmpeg
  net_test_server.py       PC side of Net-Example: TCP / UDP echo server
  gen_libm_syms.py         regenerates lib/libm/redefine.syms
NewProjectTemplate/   a starting point: sprite, text, input and sound on lib/vito and lib/gfx -> MyGame.vpk
Examples/
  Framebuffer-Example/  raw framebuffer, no graphics library (the template before lib/gfx)
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
  Net-Example/          lib/net: connection info, DNS, HTTP, TCP and UDP with a PC
  Media-Example/        Ogg music streaming, MP4 video, camera
docs/
  getting-started.md    setup, how the build works, each helper, and the gotchas hit on real hardware
  roadmap.md            what is done, what was measured, what is left
  gxp-format.md         notes on the compiled shader format
```

AI may be used to generate these bindings to speed up the time it takes to development and to solve issues / bugs along the way
