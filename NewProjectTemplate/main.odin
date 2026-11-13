package my_game

// A starting point for a game: one sprite you move with the d-pad or the left
// stick, some text, and a sound on Cross.
//
//   lib/vito   start-up, memory, input, timing, files, audio
//   lib/gfx    drawing: sprites, shapes and text (and 3D with your own
//              shaders, see Examples/Gxm-Example)
//   lib/sce    the raw VitaSDK calls, when the helpers do not cover something
//
// Everything in the assets folder is packed into the .vpk by build.bat and is
// read at run time from "app0:/assets/...".
//
// Hold Start + Select for a second to exit.

import "core:fmt"

import gfx  "../lib/gfx"
import sce  "../lib/sce"
import vito "../lib/vito"

PLAYER_SPEED :: 300 // pixels per second

// Start-up problems cannot be shown on a screen that is not set up yet, so
// they go to a file: ux0:data/my_game_error.txt
fail :: proc(what: string) -> i32 {
    text := fmt.tprintf("%s\ngfx step %v, error 0x%08X, alloc 0x%08X\n",
        what, gfx.init_step, u32(gfx.init_error), u32(gfx.last_alloc_error))
    vito.print(text)
    vito.write_entire_file("ux0:data/my_game_error.txt", transmute([]u8)text)
    return sce.sceKernelExitProcess(1)
}

// Reads a file from the package. The data stays allocated; free it with
// delete when it is no longer needed.
asset :: proc(path: cstring) -> []u8 {
    data, ok := vito.read_entire_file(path)
    if !ok do vito.printf("could not read %s\n", path)
    return data
}

// The proc name can be anything; the link_name is what main.c calls.
@(export, link_name = "odin_main")
game_main :: proc "c" (argc: i32, argv: [^]cstring) -> i32 {
    // Sets up the heap, the temp allocator, the logger and assertions.
    // Without it new / make / append do nothing on the Vita.
    context = vito.init()

    vito.input_init({})               // add .Front_Touch, .Back_Touch, .Motion as needed
    audio_ok := vito.audio_init()

    if !gfx.init() do return fail("gfx.init failed")              // gfx.init({multisample = ._4X}) for antialiasing
    if !gfx.draw2d_init() do return fail("gfx.draw2d_init failed")

    // ---- assets -------------------------------------------------------
    ok: bool
    player: gfx.Texture
    {
        png := asset("app0:/assets/player.png")
        defer delete(png)
        if player, ok = gfx.load_png(png); !ok do return fail("assets/player.png")
    }
    font: gfx.Font
    {
        png, fnt := asset("app0:/assets/font20.png"), asset("app0:/assets/font20.fnt")
        defer delete(png)
        defer delete(fnt)
        if font, ok = gfx.load_font(png, fnt); !ok do return fail("assets/font20")
    }
    blip, blip_ok := vito.load_wav("app0:/assets/blip.wav")

    // ---- game state -----------------------------------------------------
    position := [2]f32{gfx.WIDTH / 2, gfx.HEIGHT / 2}
    angle: f32
    presses := 0

    input: vito.Input
    timer: vito.Frame_Timer
    exit_hold := 0

    for {
        dt := vito.frame_tick(&timer) // seconds since the last frame
        vito.input_update(&input)

        if vito.held(input, vito.BUTTON_START) && vito.held(input, vito.BUTTON_SELECT) {
            exit_hold += 1
            if exit_hold > 60 do break
        } else {
            exit_hold = 0
        }

        // ---- update -------------------------------------------------------
        // dpad and left_stick are both -1..1 on each axis, +y down.
        move := vito.dpad(input) + input.left_stick
        position += move * PLAYER_SPEED * dt
        position.x = clamp(position.x, 0, gfx.WIDTH)
        position.y = clamp(position.y, 0, gfx.HEIGHT)
        angle += dt

        if vito.pressed(input, vito.BUTTON_CROSS) {
            presses += 1
            if blip_ok do vito.play_sound(blip)
        }

        // ---- draw -----------------------------------------------------------
        gfx.begin_frame()
        gfx.clear({0.08, 0.10, 0.18, 1})
        gfx.begin_2d()

        w, h := f32(player.width), f32(player.height)
        gfx.draw_texture_ex(&player, {0, 0, w, h}, {position.x, position.y, w, h}, origin = {w / 2, h / 2}, rotation = angle)

        gfx.draw_text(&font, 24, 36, "My Game", gfx.WHITE, 1.5)
        gfx.draw_text(&font, 24, 64, "D-pad or left stick: move     Cross: sound", gfx.rgba(170, 170, 170))
        gfx.draw_text(&font, 24, 92, fmt.tprintf("Cross pressed %d times     %.0f fps", presses, timer.fps), gfx.rgba(240, 220, 60))
        if !audio_ok || !blip_ok do gfx.draw_text(&font, 24, 120, "audio is not available", gfx.rgba(250, 100, 100))
        gfx.draw_text(&font, 24, 530, "Hold Start + Select to exit", gfx.rgba(240, 220, 60) if exit_hold > 0 else gfx.rgba(170, 170, 170))

        gfx.end_2d()
        gfx.end_frame()
        gfx.swap()

        // Everything made with the temp allocator this frame (fmt.tprintf above).
        free_all(context.temp_allocator)
    }

    // ---- shutdown: the GPU must be idle before its memory is released -------
    vito.stop_all_voices()
    if blip_ok do vito.unload_sound(&blip)
    vito.audio_shutdown()

    gfx.finish()
    sce.sceGxmDisplayQueueFinish()
    gfx.destroy_font(&font)
    gfx.destroy_texture(&player)
    gfx.draw2d_shutdown()
    gfx.shutdown()

    vito.input_shutdown()
    vito.shutdown()
    sce.sceKernelExitProcess(0)
    return 0
}
