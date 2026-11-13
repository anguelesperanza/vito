# Getting started

How to build a PS Vita `.vpk` from Odin source on Windows with `build.bat`.

Only things that were run and worked are listed here. Anything not yet tested is
under [Not verified](#not-verified).

**Tested with:** Windows 11, Odin `dev-2026-11:e28f5d1ff`, VitaSDK `2026.08`
(`arm-vita-eabi-gcc` 15.2.0), Vita3K v0.2.1, and a hacked PS Vita.
The template and the vita2d example were run on the emulator **and** on real
hardware. The touch example was run on real hardware only. The audio example
ran on both (the emulator's audio was fine from the start; the hardware needed the
double-buffering fix in gotcha 13).

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

cd Examples\Audio-Example    # 4-key synthesizer: audio output + a thread
.\build.bat                  # -> Audio-Example.vpk

cd Examples\Runtime-Example  # allocator, fmt, maps, log, threads, assertions
.\build.bat                  # -> Runtime-Example.vpk

cd Examples\SaveData-Example # save file, SceAppUtil, power, assets, LiveArea
.\build.bat                  # -> SaveData-Example.vpk

cd Examples\Input-Example    # buttons, sticks, both touch panels, motion
.\build.bat                  # -> Input-Example.vpk

cd Examples\Sync-Example     # mutex, semaphore, event flag, threads, frame timer
.\build.bat                  # -> Sync-Example.vpk

cd Examples\Mixer-Example    # audio mixer, WAV files, BGM / VOICE ports, microphone
.\build.bat                  # -> Mixer-Example.vpk

cd Examples\System-Example   # dialogs, on-screen keyboard, power events, system modules
.\build.bat                  # -> System-Example.vpk

cd Examples\Gxm-Example      # SceGxm with our own shaders: 3D, textures, lighting
.\build.bat                  # -> Gxm-Example.vpk

cd Examples\Sprite-Example   # 2D on SceGxm: sprites, shapes, text, over a 3D scene
.\build.bat                  # -> Sprite-Example.vpk

cd Examples\GxmFeatures-Example   # stencil, mipmaps, texture formats, instancing
.\build.bat                  # -> GxmFeatures-Example.vpk

cd Examples\Net-Example      # Wi-Fi info, DNS, HTTP / HTTPS, TCP and UDP sockets
.\build.bat                  # -> Net-Example.vpk

cd Examples\Media-Example    # Ogg music streaming, MP4 video, camera
.\build.bat                  # -> Media-Example.vpk
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
| `Examples/Audio-Example`  | `ODIN00004` | Hold Cross / Circle / Square / Triangle to play C4 / E4 / G4 / C5 (sine voices on an audio thread). D-pad Up/Down: octave. Left/right shoulder: volume. Level meter on screen |

### The Odin runtime (`lib/vito`)

On `freestanding_arm32` Odin's default allocator is the nil allocator and its
assertion handler prints nothing. So without help, `new`, `make`, `append`, maps,
`strings.Builder`, `fmt.tprintf` and `core:log` silently do nothing, and a failed
`assert` just traps. `lib/vito` fills that in. Start the entry procedure with:

```odin
context = vito.init()      // instead of runtime.default_context()
```

- **Heap:** `context.allocator` is newlib's `malloc` family (integer-only calls, no
  bridge). newlib takes one block at start-up, 128 MiB by default; to change it,
  define `unsigned int _newlib_heap_size_user` in `main.c` (the template has the line
  commented out).
- **Temp allocator:** a growing arena (1 MiB first block). Call
  `free_all(context.temp_allocator)` once per frame.
- **Other threads and callbacks:** every `proc "c"` needs its own
  `context = vito.thread_context()`. That context shares the heap (newlib locks it)
  but its temp allocator is the heap, because the arena is not thread-safe.
- **Printing:** `vito.print` / `println` / `printf` format with `core:fmt` into a
  1 KiB stack buffer and write through `sceClibPrintf`. `context.logger` is set, so
  `core:log` works.
- **Assertions and `panic`:** the message and source location are printed, appended to
  `ux0:data/vito_panic.log` (a console has no log window), and then the program traps,
  which gives the crash screen and a core dump. `vito.panic_action = .Exit` closes the
  app quietly instead. Bounds-check failures do not go through this handler: the Odin
  runtime traps on those directly with no message.
- `vito.init()` also runs Odin's global initialisers and `@(init)` procedures. Nothing
  else does, because the build uses `-no-entry-point`.
- Link `-lSceIofilemgr_stub` as well (for the panic log).

`core:fmt`, `core:log`, `core:strings`, `core:strconv`, `core:slice`, `core:math` and
`core:math/linalg` all build for this target. `Examples/Runtime-Example` runs twelve
checks over them and shows PASS or FAIL for each; Triangle fails an assertion on
purpose. All twelve checks pass on a real Vita, and the on-purpose assertion gives the
crash screen, a core dump and the line in `ux0:data/vito_panic.log`. Not tried in Vita3K.

### Assets, LiveArea and save data

**Assets.** `build.bat` packs the project's `assets\` folder into the VPK. At run time
the files are under `app0:/assets/` (read-only), e.g.
`v2d.LoadPNGFile("app0:/assets/test.png")` or `sce.sceIoOpen("app0:/assets/level1.bin", ...)`.

**LiveArea (the bubble and its screen).** `build.bat` also packs `sce_sys\` when it
exists. The files and their required sizes:

| File | Size | What it is |
|---|---|---|
| `sce_sys\icon0.png` | 128 x 128 | the bubble on the home screen |
| `sce_sys\pic0.png` | 960 x 544 | shown while the app loads |
| `sce_sys\livearea\contents\bg.png` | 840 x 500 | LiveArea background |
| `sce_sys\livearea\contents\startup.png` | 280 x 158 | the picture you press to start |
| `sce_sys\livearea\contents\template.xml` | | names the two images above |

Every PNG must be exactly that size and **8-bit indexed colour** (a 256-entry palette),
not truecolour. `python tools\make_livearea.py <project folder> "Title"` writes
placeholder images that follow the rules (it needs Pillow); replace them with your own
art converted the same way, for example with `pngquant 256`. Without `sce_sys\` the
bubble gets the system's default icon.

**Save data.** Call `sceAppUtilInit` once (both parameter structs zeroed) before using
save data or `sceAppUtilSystemParamGet*`. `Examples/SaveData-Example` writes a small
struct to `savedata0:/save.bin`, the app's own save area, and falls back to
`ux0:data/<title id>/` if that cannot be written; the screen shows which one was used.
It also creates a save-data slot (the title and subtitle the system shows for a save),
reads the language, the enter button (Circle or Cross, by region) and the user name,
and shows battery and clock speeds from `ScePower`. Link `-lSceAppUtil_stub
-lScePower_stub -lSceRtc_stub -lSceIofilemgr_stub`.

Confirmed on a real Vita: the score and launch count survive closing and restarting
the app. Not recorded yet: which of the two save locations was used, whether the slot
line is green, and whether the bubble shows the custom icon.

### The input layer (`lib/vito/input.odin`)

Instead of polling `SceCtrl`, `SceTouch` and `SceMotion` by hand:

```odin
vito.input_init({.Front_Touch, .Back_Touch, .Motion})   // once
input: vito.Input
for {
    vito.input_update(&input)                            // once per frame
    if vito.pressed(input, vito.BUTTON_CROSS) do jump()
    if vito.held(input, vito.BUTTON_L | vito.BUTTON_R) do brake()
    move := input.left_stick                             // -1..1, y down, dead zone applied
    for t in vito.touches(&input.front) do tap(t.pos)    // screen pixels
}
```

- `pressed` and `released` are true for one frame; `held` while the button is down.
  A mask with several buttons means "any of them".
- `BUTTON_L` / `BUTTON_R` cover both the handheld's shoulder buttons and a DualShock's
  L1 / R1 (gotcha 15).
- Sticks use a round dead zone, `vito.stick_dead_zone` (default 0.15), and are rescaled
  so movement starts from zero at its edge.
- Each `Touch` has a stable `id` while the finger is down, `pos` in screen pixels (the
  back panel is mapped onto the same 960 x 544), `force`, and `pressed` on its first
  frame. `panel.released_ids[:panel.released_count]` lists fingers lifted this frame.
- `input.motion` has `acceleration` (g), `gyro` (rad/s), `orientation` (quaternion) and
  a `valid` flag.
- `input.raw` is the untouched `sce.CtrlData`.
- Link `-lSceCtrl_stub -lSceTouch_stub -lSceMotion_stub`. All three are needed as soon
  as `input_update` is called, even if touch and motion are not asked for.

**Stub libraries every `lib/vito` project links.** Odin emits every procedure of an
imported package, used or not, so a project that imports `lib/vito` needs the stubs
for all of it: `-lSceCtrl_stub -lSceTouch_stub -lSceMotion_stub -lSceAudio_stub
-lSceCommonDialog_stub -lSceAppUtil_stub -lScePower_stub -lSceAppMgr_stub
-lSceKernelThreadMgr_stub -lSceIofilemgr_stub -lSceSysmem_stub -lSceLibKernel_stub`.
A missing one shows as `undefined reference to sce...` at link time. Linking a stub
costs nothing at run time.

### Frame timing (`lib/vito/time.odin`)

```odin
timer: vito.Frame_Timer
for {
    dt := vito.frame_tick(&timer)   // seconds since the previous frame
    ...
}
```

`timer.fps` is averaged over half a second, `timer.elapsed` is seconds since the first
tick, and a frame longer than `timer.max_delta` (default 0.1 s) reports that limit, so
a long load or a suspend does not make game logic jump. `vito.time_us()` is the raw
process clock in microseconds and `vito.sleep_ms(n)` blocks the calling thread.

### Kernel sync objects

`Examples/Sync-Example` uses each of these between two real threads and shows PASS or
FAIL per check: mutex (including try-lock), lightweight mutex, semaphore (including a
timeout), event flag, condition variable, read/write lock, message pipe, thread
information, priority and CPU affinity, `sceKernelDelayThread`, `sceKernelPowerTick`
and `sceKernelAtomicAddAndGet32`. All 13 checks pass on a real Vita. Things worth
knowing when using them:

- A timeout is a **pointer to microseconds**, and the kernel writes the time that was
  left back into it. Use a fresh variable for each call; `nil` waits forever.
- `sceKernelGetThreadInfo` (and the other `Get*Info` calls) need `info.size =
  size_of(info)` set first.
- A lightweight mutex (`KernelLwMutexWork`) lives in your own memory, so it must not
  move or go out of scope while in use.
- Link `-lSceKernelThreadMgr_stub` as well as `-lSceLibKernel_stub`.

`Examples/Input-Example` shows everything live. It also makes the three `SceMotion`
calls that pass a float (`sceMotionSetAngleThreshold` and friends), so it lists `sce`
in `BRIDGES`. Note that `lib/sce/bridge.c` wraps functions from four libraries, so a
project that uses it must link `-lSceGxm_stub -lScePgf_stub -lScePvf_stub
-lSceMotion_stub` even if it only calls one of them. Confirmed on a real Vita, including the float
bridge round trip.

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

### The audio mixer (`lib/vito/audio.odin`)

For games, use the mixer instead of feeding `SceAudioOut` by hand:

```odin
vito.audio_init()
jump, _  := vito.load_wav("app0:/assets/jump.wav")
music, _ := vito.load_wav("app0:/assets/music.wav")
song := vito.play_sound(music, volume = 0.6, loop = true)
...
if vito.pressed(input, vito.BUTTON_CROSS) do vito.play_sound(jump, pan = -0.5)
vito.voice_set_volume(song, 0.3)
...
vito.audio_shutdown()            // before unload_sound and before exit
```

- `play_sound(sound, volume, pan, loop, pitch)` returns a `Voice` handle. Up to 16
  play at once; with all in use it returns 0. `stop_voice`, `voice_set_volume`,
  `voice_set_pan`, `voice_set_pitch`, `voice_set_paused` and `voice_is_playing` take
  that handle, and a handle whose sound has ended is ignored.
- `set_master_volume`, `audio_peak` (0..1, for a meter), `active_voice_count`.
- `load_wav` reads uncompressed PCM WAV: 8 or 16 bit, mono or stereo, any sample rate.
  The mixer resamples to its 48 kHz stereo output, so files do not have to match.
  Convert MP3 / Ogg / FLAC on the PC first.
- A `Sound` is just samples in memory, so one can also be built by hand:
  `vito.Sound{samples = buf, channels = 1, sample_rate = 16000, frames = len(buf)}`.
- There is a delay of one or two buffers (21 to 43 ms) between `play_sound` and the
  sound.
- Link `-lSceAudio_stub -lSceKernelThreadMgr_stub -lSceIofilemgr_stub`.

`Examples/Mixer-Example` plays overlapping effects and a music loop, and also tests the
`BGM` and `VOICE` output ports and the microphone. It runs on hardware. The section
below describes the raw `SceAudioOut` calls the mixer is built on.

### Dialogs and the on-screen keyboard (`lib/vito/dialog.odin`)

The system draws its dialogs on top of the game's frame, so the game keeps running
its loop while one is open. Three things are needed:

```odin
vito.dialog_init()                    // once; also calls sceAppUtilInit

// every frame, between the end of the scene and the swap:
v2d.EndDrawing()
v2d.CommonDialogUpdate()
v2d.SwapBuffers()

// open one, then poll it every frame until done:
vito.message_dialog_open("Save before quitting?", .Yes_No)
if result, done := vito.message_dialog_poll(); done {
    if result.button == 1 { /* Yes */ }
}

vito.text_input_open("Your name", "Player", 32)
buf: [128]u8
if text, accepted, done := vito.text_input_poll(buf[:]); done && accepted {
    // text is UTF-8, stored in buf
}
```

- Only one dialog can be open at a time; an `*_open` call returns false otherwise, or
  when the system refuses it (`vito.dialog_last_error` has the code).
- Buttons still reach the game while a dialog is open. Skip the game's own input when
  `vito.dialog_active()` is true.
- `result.button` is 1 for OK, Yes or the first custom button, 2 for No or the second,
  3 for the third. `result.canceled` is set when the user backed out or the game
  closed the dialog.
- Also there: `error_dialog_open(code)`, `system_message_dialog_open(type)`,
  `progress_dialog_open(text)` with `progress_dialog_set(percent)` and
  `message_dialog_close()`, and `dialog_abort()`.
- The keyboard and several other system APIs use UTF-16: `vito.to_utf16(dst, s)` and
  `vito.from_utf16(buf, src)` convert.

### Suspend, resume and power events (`lib/vito/system.odin`)

A game is not asked before it is suspended (PS button, power button, idle timeout); it can
only find out afterwards. `vito.power_events_start()` starts a small thread that
receives the system's power callback, and `vito.power_events_take()` returns the
`sce.POWER_CB_*` flags that arrived since the last call:

```odin
events := vito.power_events_take()
if events & sce.POWER_CB_APP_RESUME != 0 { /* back from the LiveArea: pause, reset timers */ }
```

`vito.system_event_poll()` reports `SceAppMgr` events (resume among them), and
`vito.system_ui_overlaid()` is true while the system draws over the game.

Optional system modules (`SceIme`, `SceNet`, `SceNotificationUtil`, `SceScreenShot`,
...) must be loaded with `sce.sceSysmoduleLoadModule(.NAME)` before their functions
are called; until then the calls fail.

`Examples/System-Example` uses all of this, and runs on hardware.

### 3D and custom shaders (`lib/gfx`, `SceGxm`)

`vita2d` covers 2D. For 3D, or any drawing with your own shaders, `lib/gfx` sets
`SceGxm` up and the drawing is done with the `sce.sceGxm*` calls. It runs on
hardware; `Examples/Gxm-Example` is the reference.

**Shaders.** `SceGxm` only runs compiled `.gxp` programs. Shaders are written in Cg,
one file per program, named `NAME_v.cg` (vertex) or `NAME_f.cg` (fragment), and
compiled on the PC:

```
python tools\build_shaders.py Examples\Gxm-Example\shaders
```

That needs Sony's `psp2cgc.exe` at `tools\psp2cgc.exe` (or `PSP2CGC` set to its
path). The compiler is proprietary and git-ignored; the `.gxp` files it writes are
checked in, so building a project does not need it. A program is embedded and
registered with `gfx.register_program(#load("shaders/color_v.gxp"))`.

**A frame.**

```odin
gfx.init({multisample = ._4X})         // or gfx.init() for no antialiasing

gfx.begin_frame()
gfx.clear({0, 0, 0, 1})
vertex_uniforms, fragment_uniforms := gfx.use_programs(vertex_program, fragment_program)
gfx.set_uniform_matrix(vertex_uniforms, mvp_param, &mvp)
sce.sceGxmSetVertexStream(gfx.ctx, 0, vertices)
sce.sceGxmDraw(gfx.ctx, .TRIANGLES, .U16, indices, index_count)
gfx.end_frame()
gfx.swap()
```

Rules that differ from OpenGL-style APIs:

- Vertices, indices and textures must be in memory mapped for the GPU: `gfx.alloc`,
  not `new` or `make`. Blocks are rounded up to 4 KiB (256 KiB in video memory), so
  pack small meshes into one block.
- Do not free or rewrite that memory while a frame using it may still be rendering;
  `gfx.finish()` waits for the GPU.
- A vertex program is tied to one vertex layout, and a fragment program to one blend
  mode and one multisample mode. Blending is not a state you switch: make a second
  fragment program (`gfx.create_fragment_program(f, v, .Alpha)`).
- Uniforms live in a buffer reserved per program selection. Call `gfx.use_programs`
  again before a draw that needs different uniform values.
- Clip space is as in OpenGL, and `core:math/linalg`'s `matrix4_perspective_f32` and
  `matrix_ortho3d_f32` match it. Pass Odin's matrix memory unchanged and write
  `mul(vector, matrix)` in the shader.
- To draw into a texture: `gfx.create_target`, then `gfx.begin_target` ...
  `gfx.end_frame` before `gfx.begin_frame`. Fragment programs used there need
  `target_multisample = .NONE`.
- Link `-lSceGxm_stub -lSceDisplay_stub -lSceCommonDialog_stub -lpng16 -lz` and put
  `sce` in `BRIDGES` (`sceGxmSetViewport` takes floats).

### 2D on `lib/gfx`: sprites, shapes and text

The same package draws 2D, so a game can do without `vita2d` and put a HUD over a
3D scene in one frame. It runs on hardware; `Examples/Sprite-Example` is the
reference.

```odin
gfx.init()
gfx.draw2d_init()
player, _ := gfx.load_png(png_bytes)                 // from vito.read_entire_file or #load
font, _   := gfx.load_font(#load("assets/font20.png"), #load("assets/font20.fnt"))

gfx.begin_frame()
gfx.clear({0, 0, 0, 1})
// ... any 3D drawing ...
gfx.begin_2d()
gfx.draw_texture(&player, 100, 200)
gfx.draw_texture_ex(&sheet, {0, 0, 32, 32}, {400, 300, 64, 64}, origin = {32, 32}, rotation = angle)
gfx.draw_rect(0, 0, 960, 40, gfx.rgba(0, 0, 0, 128))
gfx.draw_text(&font, 16, 30, "Score 100")
gfx.end_2d()
gfx.end_frame()
gfx.swap()
```

- Coordinates are pixels from the top left. Colours are `0xAABBGGRR`
  (`gfx.rgba(r, g, b, a)`); a texture is multiplied by the colour.
- `draw_texture_ex` takes the part of the texture to draw (`src`), where and how big
  (`dst`), the point it sits on and turns around (`origin`), a rotation in radians,
  a colour and two flip flags.
- Sprites drawn one after another from the same texture become one draw call. Put
  small images on one sheet and draw by texture where the order allows.
  `gfx.draw2d_stats()` reports quads and draw calls for the last frame.
- A frame holds at most `gfx.MAX_QUADS_PER_FRAME` (8192) quads; more are dropped and
  counted in `gfx.draw2d_dropped()`.
- `gfx.set_blend(.Additive)` switches blending inside `begin_2d` / `end_2d`.
- `begin_2d` also works inside `begin_target`, in the target's pixels.

**Fonts** are baked on the PC into an atlas (a PNG and a `.fnt` file):

```
python tools\make_font.py C:\Windows\Fonts\DejaVuSans.ttf 20 assets\font20 --chars latin1
```

Text is sharpest at the baked size; bake one atlas per size that matters. Check the
font's licence before shipping an atlas made from it. `gfx.measure_text` gives the
size of a string for alignment.

### More `SceGxm`: stencil, mipmaps, texture formats, instancing

`Examples/GxmFeatures-Example` has one page for each of these, and runs on
hardware. The short version of each:

- **Stencil.** The depth buffer `lib/gfx` creates has 8 stencil bits, reset at the
  start of every scene. Write with `sce.sceGxmSetFrontStencilRef` and
  `sce.sceGxmSetFrontStencilFunc(ctx, .ALWAYS, .KEEP, .KEEP, .REPLACE, 0xFF, 0xFF)`,
  test with `.EQUAL` / `.NOT_EQUAL`. To write stencil without colour, use a fragment
  program made with `gfx.create_fragment_program_blend` and
  `colorMask = sce.GXM_COLOR_MASK_NONE`.
- **Other texture formats.** `gfx.create_texture_format(width, height, format, bytes,
  layout, mip_count)` gives raw memory to fill. Mipmaps and block-compressed formats
  need the `.Swizzled` layout: power-of-two sizes, pixels (or 4 x 4 blocks) in Morton
  order, at index `gfx.swizzle(x, y)`. Mip levels follow each other, largest first,
  and are used once `sce.sceGxmTextureSetMipFilter(&t.texture, .ENABLED)` is called.
  A paletted texture needs its 256-colour palette in `gfx.alloc` memory too
  (`sce.sceGxmTextureSetPalette`).
- **Lines and points.** Draw with `.LINES` or `.POINTS` and set the matching polygon
  mode first (`sce.sceGxmSetFrontPolygonMode(ctx, .LINE)` or `.POINT`); set it back
  to `.TRIANGLE_FILL` afterwards. Line width is `sce.sceGxmSetFrontPointLineWidth`;
  a point's size is a `PSIZE` output of the vertex shader. `.TRIANGLE_LINE` draws
  triangles as wireframe.
- **Instancing.** Give the per-instance values their own vertex stream with
  `indexSource = sce.GXM_INDEX_SOURCE_INSTANCE_16BIT`
  (`gfx.create_vertex_program_streams`), then
  `sce.sceGxmDrawInstanced(ctx, .TRIANGLES, .U16, indices, indices_per_instance *
  instances, indices_per_instance)`.
- **Region clip.** `sce.sceGxmSetRegionClip(ctx, .OUTSIDE, x0, y0, x1, y1)` limits
  drawing to a rectangle; `.NONE` turns it off. On a real Vita `.INSIDE` does the
  same as `.OUTSIDE` (it also keeps the inside), so to draw everywhere except a
  rectangle use the stencil buffer instead.

What is known about the compiled shader format is in [gxp-format.md](gxp-format.md);
`python tools\gxp_info.py file.gxp` prints a shader's parameters.

### Networking (`lib/net`)

`lib/net` starts the network libraries and wraps sockets, name lookup and HTTP.
Sockets, DNS and plain HTTP run on hardware; **HTTPS to current servers does not work** (see
below). `Examples/Net-Example` is the reference.

```odin
net.init()                                   // once; net.init(http = false) for sockets only
if !net.connected() { /* no Wi-Fi */ }

response, ok := net.http_get("http://example.com/")
if ok {
    // response.status, response.body ([]u8)
    net.http_free(&response)
}

address, _ := net.resolve("example.com", 80)   // or net.parse_ip("192.168.1.10", 9999)
socket, _  := net.tcp_connect(address)
net.send_all(socket, data)
n := net.receive(socket, buffer[:])            // 0: closed by the other side; < 0: error
net.close(socket)
```

- **Every call waits** for the other side or a timeout. Make them from a second
  thread, as the example does, or the picture freezes. `net.set_non_blocking` is
  there for sockets polled from the game loop instead.
- UDP: `net.udp_open`, `net.udp_send`, `net.udp_receive`. A server: `net.tcp_listen`
  and `net.tcp_accept`.
- `net.info()` returns the IP address, gateway, DNS, Wi-Fi name and signal strength.
- **HTTPS** checks certificates against the console's own list of authorities, which
  has not been updated for years, so many current sites fail. `net.https_set_verify(false)`
  turns the check off: still encrypted, but the server is no longer proven to be who
  it claims. After a failure `net.last_http_step`, `net.last_error`
  (`net.http_error_name` gives it a name) and `net.last_ssl_error` say where and why.
  **On hardware, HTTPS to a current server (`https://example.com/`) fails in the
  TLS handshake** (`HTTPS_ERROR_HANDSHAKE`), before certificates are checked: the
  console's TLS versions and ciphers are too old, and no setting here helps. Reaching
  such servers needs a TLS library shipped with the game. That is deferred; the plan
  for adding it is under "To revisit" in [roadmap.md](roadmap.md).
- Link `-lSceNet_stub -lSceNetCtl_stub -lSceHttp_stub -lSceSsl_stub -lSceSysmodule_stub`.

To test sockets, run the PC side and type the address it prints into the example:

```
python tools\net_test_server.py
```

### Music, video and the camera

`Examples/Media-Example` covers all three, and all three run on hardware.

**Music (`lib/vorbis`).** Long music as WAV is about 11 MB a minute; as Ogg Vorbis it
is about 1 MB and is decoded while it plays.

```odin
vito.audio_init()
data, _ := vito.read_entire_file("app0:/assets/music.ogg")
music, ok := vorbis.open(data)            // keeps reading from data
vorbis.play(music, volume = 0.8, loop = true)
// vorbis.set_paused, set_volume, seek, position, duration, is_playing
vorbis.close(music)                       // then data may be freed
```

- Add `vorbis` to `BRIDGES` in `build.bat`: the decoder (`stb_vorbis`) is a C file
  compiled with the project.
- Effects played with `vito.play_sound` mix with it. Convert on the PC with
  `ffmpeg -i song.wav -c:a libvorbis -q:a 4 song.ogg`.
- Underneath is `vito.play_stream(fill, user, sample_rate)`, which plays whatever a
  callback produces; use it directly for generated sound or another decoder. The
  callback runs on the audio thread and must not block.

**Video (`lib/video`).** MP4 with H.264 video and AAC sound, decoded by the console's
hardware. It needs `lib/gfx` (not `vita2d`).

```odin
movie, ok := video.open("app0:/assets/intro.mp4")
// every frame:
video.update(movie)
if movie.has_frame {
    gfx.set_blend(.None)       // a video picture has no alpha
    gfx.draw_texture_ex(&movie.texture, {0, 0, f32(movie.width), f32(movie.height)}, {0, 0, 960, 544})
    gfx.set_blend(.Alpha)
}
if video.finished(movie) { /* done */ }
// at the end:
gfx.finish()
video.close(movie)
```

- Encode for it with, for example: `ffmpeg -i in.mov -c:v libx264 -profile:v baseline
  -level 3.1 -pix_fmt yuv420p -vf scale=960:544 -r 30 -c:a aac -ar 48000 -ac 2
  -movflags +faststart out.mp4`
- Its sound uses the `BGM` audio port, so it plays alongside the mixer.
- Link `-lSceAvPlayer_stub -lSceAudio_stub`.

**Camera.** There is no helper; the example's `camera_start` / `camera_update` show
the calls. The camera writes each picture into memory you give it, so pointing it at
a `gfx` texture's pixels shows it with no copying. Link `-lSceCamera_stub`.

### Audio output and threads

`lib/sce/audioout.odin` binds `SceAudioOut` (link `-lSceAudio_stub`) and
`lib/sce/kernel_threadmgr_thread.odin` binds the thread calls (link `-lSceLibKernel_stub` and
`-lSceKernelThreadMgr_stub`). Everything is integer or pointer arguments, so no
float bridge is needed.

- Open a port: `sceAudioOutOpenPort(.MAIN, grain, 48000, .MONO)`. `grain` is the
  number of samples per buffer, a multiple of 64 (the example uses 1024, about
  21 ms). A `.MONO` port takes one `i16` per sample.
- Feed it with `sceAudioOutOutput(port, buf)`. This call **blocks**, so run it on
  its own thread, not in the render loop (a slow frame would starve the audio, and
  waiting on audio would stall the frame rate).
- **Use two buffers and alternate them** (gotcha 13).
- Create the thread with `sceKernelCreateThread(name, entry, priority, stack, 0, 0,
  nil)` and `sceKernelStartThread`. The entry is a `proc "c" (args: u32, argp:
  rawptr) -> i32`. The values `THREAD_DEFAULT_PRIORITY_USER` (`0x10000100`) and
  `THREAD_DEFAULT_STACK_SIZE` (`0x10000`) come from the header's own example.
- Share flags between threads with `intrinsics.volatile_load` / `volatile_store`
  on aligned 32-bit values (what the example does), or with `intrinsics.atomic_*`
  now that the build targets the Cortex-A9 (gotcha 14).
- Shut down by clearing a `running` flag, `sceKernelWaitThreadEnd`, then
  `sceKernelDeleteThread`, then `sceAudioOutOutput(port, nil)` (waits for the last
  grain to play out) and `sceAudioOutReleasePort`.
- `sceAudioOutSetVolume(port, L_CH | R_CH, &vols[0])` takes a pointer to two `i32`
  (left, right), each 0..32768.
- The example's audio thread uses integer math only (a check of the generated
  assembly found no float instructions in it). It builds its sine table with
  `math.sin` on the main thread before the thread starts, then only reads the table.

---

## How the pipeline works

```
main.odin
   │  odin build . -target:freestanding_arm32 -build-mode:asm -no-entry-point
   ▼                -min-link-libs -no-thread-local -o:speed -microarch:cortex-a9
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

There are three places this shows up, and all are handled:

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
   calling the real functions.

   `redefine.syms` lists **every** libm function (308 names, written by
   `tools/gen_libm_syms.py`), not only the wrapped ones. A libm call with no wrapper
   therefore fails at link time with ``undefined reference to `vito_<name>'``, and the
   fix is to add that function to `lib/libm/bridge.c`. Before this, such a call linked
   and returned garbage.
3. **libgcc helpers for 64-bit integer and float conversions.** `i64(some_float)` and
   `f64(some_u64)` compile to calls to `__fixdfdi`, `__floatundidf` and friends, which
   are hard-float in VitaSDK's libgcc. `core:fmt` and `core:strconv` use them when they
   print or parse floats. They are renamed and wrapped the same way.

To check what an Odin object calls:

```
arm-vita-eabi-nm -u build\<name>.odin.o
```

Anything that looks like a libm name (`sinf`, `powf`, `fmodf`, ...) without a
`vito_` prefix is a bug waiting to happen. The vita2d example logs a self-test at
startup (`selftest sin(1)*1e6=841470 cos(1)*1e6=540302 max(2x,-3x)=2`) to prove
the libm bridge works.

## The `sce` bindings are generated

`lib/sce/` covers the whole user-mode SDK (`psp2/*.h`, `psp2common/*.h`): 123 files,
1,649 functions. They are written by `tools/bindgen/gen.py`, not by hand:

```
python tools\bindgen\gen.py          # rewrites lib\sce\*.odin, lib\sce\bridge.c, tools\bindgen\report.md
python tools\bindgen\linkcheck.py    # links every bound function against the stub libraries
```

It needs Python 3 with `pycparser`. Run it again after updating VitaSDK.

- The generator parses the real headers and takes every struct size, field offset,
  enum value and macro value **from GCC** (it compiles a probe file), so nothing is
  typed from memory. Each struct has an `#assert(size_of(...))`; the generator also
  checks all 1,818 field offsets against GCC with `odin check`.
- It looks up which stub library exports each function. The comment at the top of
  each file lists the `-l` flags to add to `build.bat`.
- Files that start with `// GENERATED` must not be edited. Hand-written code goes in
  `sce.odin` (naming rules), `inline.odin` (the headers' `static inline` functions and
  macros, ported) and `helpers.odin`.
- `tools/bindgen/report.md` lists what was generated and what was left out.

Naming: functions keep their names; `SceCtrlData` becomes `sce.CtrlData`;
`SCE_CTRL_CROSS` becomes `sce.CTRL_CROSS`. An enum becomes an Odin enum
(`sce.TouchSamplingState.START`) only when a function or struct actually uses that
type; bit flags, error codes and enums nothing takes by type are plain constants.
Error codes are written so they compare directly with the `i32` a function returns
(`if ret == sce.CTRL_ERROR_INVALID_ARG`).

**Verified by the tools, not on a console:** names, layouts, values, link libraries.
**Not verified:** behaviour. Only the functions the examples call have run on a Vita
or in Vita3K; see [Not verified](#not-verified).

## Writing bindings for other libraries

For libraries outside the SDK (as `lib/vita2d` was), look at the real headers before
writing a struct or constant:

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

Add `#assert(size_of(...))` for every struct, with the size taken from the compiler
(`sizeof` in a small C file built with `arm-vita-eabi-gcc -S`), not worked out by hand.

**Enums are not always 4 bytes.** VitaSDK's GCC uses short enums: `sizeof` of an enum
whose values fit in a byte is 1. This changes struct layouts and anything written
through a pointer. In `lib/sce` every Odin enum is 32-bit (so arguments fill the whole
register) and a struct field whose C type is a short enum is declared as `u8`/`u16`.

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
13. **Audio: alternate two buffers.** `sceAudioOutOutput` returns before the
    hardware has finished reading the buffer you gave it. Refilling the same buffer
    straight away corrupts the audio still playing: on real hardware this was a
    low buzz at the grain rate (about 47 Hz for 1024 samples at 48 kHz), heard
    under the notes like a second, lower sound. Vita3K copies the buffer at once
    and hides it. Fill buffer A while B plays, then swap. The example's buffers are
    also 64-byte aligned.
14. **Build with `-microarch:cortex-a9`** (every `build.bat` does). Without it Odin
    targets ARMv6 (`arm1176jzf-s`), and `intrinsics.atomic_*` compiles to a CP15
    `mcr p15, 0, rX, c7, c10, 5` barrier, which is deprecated on the Vita's Cortex-A9
    and may raise an undefined instruction fault (never tested). With the flag the
    same code uses `dmb ish` and `ldrex`/`strex`, which are normal ARMv7. To check a
    build: there must be no `mcr` in `odin_asm\*.s`. The flag was added after the
    examples were last run on hardware, so **re-run them on a Vita** before relying
    on it; the audio example still uses `volatile_load` / `volatile_store`.
17. **Do not shrink text with `PvfDrawText`'s `scale`.** vita2d rasterises each PVF
    glyph once at 10.125 pt (18 px) and draws other sizes by scaling that bitmap on
    the GPU. Its glyph atlas minifies with point sampling, so a scale below 1.0 drops
    pixel rows and columns, and its pen position is an `int`, so each scaled advance
    is truncated and letters crowd together (most visible in text that changes).
    Use `v2d.DrawText(x, y, color, scale, text)` from `lib/vita2d/text.odin`: it keeps
    one font per size, rasterised at that size (`PvfSetBaseScale`, a vito addition in
    `lib/vita2d/bridge.c` that reaches into vita2d's font struct), and draws at scale
    1.0. The PVF page of `Vita2D-Full-Example` shows both side by side. The PGF text
    functions scale a bitmap the same way and have no such helper yet. Confirmed
    fixed on a real Vita.
20. **Give a system library the memory alignment it asks for.** `SceAvPlayer` asks for
    its picture buffers through a callback with an alignment argument (1 MiB). Given
    memory aligned to only 256 KiB it reported no error: it started, then stopped
    without a picture. Pass the alignment on with `KernelAllocMemBlockOpt`
    (`attr = KERNEL_ALLOC_MEMBLOCK_ATTR_HAS_ALIGNMENT`), as `lib/video` does.
19. **Handles that are addresses look negative.** `sceAvPlayerInit` returns an `int`
    that is really a pointer, so a good handle is usually below zero as an `i32`.
    Check such results against 0, not with `< 0`. (Ordinary SCE calls do return
    negative error codes; this is the exception, and the header does not say which
    a function is.)
18. **Link with `-Wl,--defsym,__sce_headroom=0x10000`** (every `build.bat` does).
    `vita-elf-create` appends its SCE metadata (module info, import tables, NIDs;
    2,752 bytes for the audio example, more with more imports) to the end of the code
    segment and does not check that it fits before the data segment. The linker puts
    the data segment at the next 64 KiB boundary, so when the code happened to end
    less than that many bytes below a boundary, the tool wrote past the gap, corrupted
    its own heap and crashed with no message (exit code -1073740940). The next step,
    `vita-make-fself`, then printed `Cannot generate module NID: No such file or
    directory`. It looked random because any change in code size moved it; changing
    `BRIDGE_OPT` only shifted the layout. VitaSDK's linker script has a symbol for this,
    `__sce_headroom`, which adds that much space before the data segment. Measured: the
    failing layout packs with it, and fails without it for every code end within the
    last 2.7 KB of a 64 KiB block. `build.bat` also now stops if `vita-elf-create`
    crashes: `if errorlevel 1` does not catch a negative exit code.
16. **Do not edit `.bat` files with Git Bash `sed -i`.** It rewrote them with LF
    endings, which then ran the wrong script (gotcha 1).
15. **The handheld's shoulder buttons are `CTRL_LTRIGGER` / `CTRL_RTRIGGER`, not
    `CTRL_L1` / `CTRL_R1`.** A volume control that only listened for `L1`/`R1`
    never reacted on the real Vita. The example accepts both pairs. (`L1`/`R1`
    are the PS TV / DualShock buttons. The header calls the trigger pair "L2/R2".)

---

## Not verified

- **`sceGxmSetRegionClip` with `.INSIDE`.** On hardware it gave the same result as
  `.OUTSIDE` (only the inside of the rectangle is drawn). Marked to revisit; the open
  questions are listed under "To revisit" in [roadmap.md](roadmap.md).
- **The generated `sce` bindings beyond what the examples call.** They link and their
  layouts match GCC, but most of the 1,649 functions have never been called on a Vita.
- **64-bit arguments: checked in the assembly, not yet on hardware.** On ARM32 a `u64`
  argument must start in an even-numbered register. O3DX found an older Odin did not
  do that. Odin `dev-2026-11` does: for `proc "c" (a: i32, b: u64)` it puts `b` in
  `r2:r3`, and with three or more integer arguments before it the `u64` goes on the
  stack 8-byte aligned. Small structs by value, struct returns, narrow integers and C
  variadics were checked the same way and match the AAPCS. So functions such as
  `sceIoLseek` are bound directly, with no bridge. Only `float`/`double` by value still
  needs one. Confirmed on a Vita by `sceHttpCreateRequestWithURL` (three arguments,
  then a `u64`) in `Net-Example`.
- **`-microarch:cortex-a9`** (gotcha 14): all examples build with it; none has been
  re-run on hardware or in Vita3K since it was added.
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
  emulator handles the back panel is unknown. 
- **Audio beyond what the example uses.** Confirmed on hardware: opening a `MAIN`
  mono port at 48 kHz with 1024-sample grains, double-buffered `sceAudioOutOutput`
  from a thread, `sceAudioOutSetVolume` (both channels), and the `nil` drain call.
  Bound but not exercised: `sceAudioOutSetConfig`/`GetConfig`, `SetAlcMode`,
  `GetAdopt`, stereo mode, the `BGM` and `VOICE` port types, other sample rates and
  grain sizes. The D-pad octave control and playing several keys at once were not
  explicitly confirmed.
- **Threads beyond the example.** Used: `sceKernelCreateThread`,
  `sceKernelStartThread`, `sceKernelWaitThreadEnd`, `sceKernelDeleteThread`,
  `sceKernelExitThread`. `sceKernelExitDeleteThread` is bound but unused. Thread
  priority and CPU affinity were left at the defaults and not tuned.
